package com.example.offline_tutor_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pGroup
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import androidx.core.content.ContextCompat
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.FileReader
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.Locale
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Legacy LAN/Wi-Fi-Direct transport (raw TCP 45888 + UDP 45889 discovery via
 * Android's built-in WifiP2pManager).
 *
 * Preferred path for new code is Google Nearby Connections
 * (Dart: NearbyP2PService, P2P_CLUSTER — encrypted, chunked, no custom crypto).
 * This manager stays only for devices without Play services. Do not add new
 * custom encryption here — route through Nearby first.
 */
class P2PManager(private val context: Context) {
    companion object {
        private const val TCP_PORT = 45888
        private const val UDP_PORT = 45889
        private const val DISCOVERY_PROBE = "DISCOVER_OFFLINE_TUTOR"
        private const val DISCOVERY_REPLY_PREFIX = "OFFLINE_TUTOR"
        private const val MAX_BUNDLE_BYTES = 50L * 1024L * 1024L
        private const val WIFI_DIRECT_DISCOVERY_WAIT_MS = 2300L
        private const val RECEIVE_APPROVAL_TIMEOUT_MS = 45_000L
    }

    private class PendingIncomingTransfer(
        val id: String,
        val senderAddress: String,
        val fileName: String,
        val sizeBytes: Long,
        val createdAt: Long,
    ) {
        val decisionLatch = CountDownLatch(1)

        @Volatile
        var approved: Boolean? = null
    }

    private data class TransferTelemetry(
        val direction: String,
        val stage: String,
        val peerAddress: String,
        val fileName: String,
        val totalBytes: Long,
        val transferredBytes: Long,
        val startedAtMs: Long,
        val updatedAtMs: Long,
        val done: Boolean,
        val success: Boolean,
        val errorMessage: String,
    ) {
        fun toMap(): Map<String, Any> {
            val elapsedMs = (updatedAtMs - startedAtMs).coerceAtLeast(1L)
            val throughputBps = ((transferredBytes * 1000L) / elapsedMs).coerceAtLeast(0L)
            val remaining = (totalBytes - transferredBytes).coerceAtLeast(0L)
            val etaSeconds = if (throughputBps > 0L) {
                (remaining / throughputBps).toInt()
            } else {
                -1
            }

            return mapOf(
                "direction" to direction,
                "stage" to stage,
                "peerAddress" to peerAddress,
                "fileName" to fileName,
                "totalBytes" to totalBytes,
                "transferredBytes" to transferredBytes,
                "progressPct" to if (totalBytes > 0L) {
                    ((transferredBytes * 100L) / totalBytes).coerceIn(0L, 100L).toInt()
                } else {
                    0
                },
                "throughputBps" to throughputBps,
                "etaSeconds" to etaSeconds,
                "startedAt" to startedAtMs,
                "updatedAt" to updatedAtMs,
                "done" to done,
                "success" to success,
                "errorMessage" to errorMessage,
            )
        }
    }

    private val receiverRunning = AtomicBoolean(false)

    @Volatile
    private var receiverThread: Thread? = null

    @Volatile
    private var discoveryResponderThread: Thread? = null

    @Volatile
    private var tcpServerSocket: ServerSocket? = null

    @Volatile
    private var udpResponderSocket: DatagramSocket? = null

    @Volatile
    private var lastTransferError: String = ""

    @Volatile
    private var lastDiscoveredPeers: List<Map<String, String>> = emptyList()

    @Volatile
    private var activeTransport: String = "wifi-lan-tcp"

    @Volatile
    private var lastRouteDecision: String = "LAN"

    private val pendingIncomingTransfers = ConcurrentHashMap<String, PendingIncomingTransfer>()
    private val wifiDirectResolvedRoutes = ConcurrentHashMap<String, String>()

    @Volatile
    private var sendTelemetry: TransferTelemetry? = null

    @Volatile
    private var receiveTelemetry: TransferTelemetry? = null

    fun getStatus(): Map<String, Any> {
        val localIp = getLocalIpv4Address().orEmpty()
        return mapOf(
            "supported" to true,
            "enabled" to (localIp.isNotEmpty() || hasWifiDirectRuntimePermissions()),
            "pairedCount" to lastDiscoveredPeers.size,
            "transport" to activeTransport,
            "receiverRunning" to receiverRunning.get(),
            "inboxCount" to listReceivedBundles().size,
            "pendingIncomingCount" to pendingIncomingTransfers.size,
            "lastTransferError" to lastTransferError,
            "localIp" to localIp,
            "routeDecision" to lastRouteDecision,
            "routePolicy" to "lan-first,wifi-direct-fallback",
        )
    }

    fun listPeers(): List<Map<String, String>> {
        val lanPeers = discoverPeersOnLan()
        val peers = if (lanPeers.isNotEmpty()) {
            activeTransport = "wifi-lan-tcp"
            lastRouteDecision = "LAN"
            lanPeers
        } else {
            val directPeers = discoverPeersOnWifiDirect()
            if (directPeers.isNotEmpty()) {
                activeTransport = "wifi-direct-discovery"
                lastRouteDecision = "WIFI_DIRECT_FALLBACK"
            } else {
                activeTransport = "wifi-lan-tcp"
                lastRouteDecision = "NONE"
            }
            directPeers
        }

        lastDiscoveredPeers = peers
        return peers
    }

    fun startReceiver(): Map<String, Any> {
        if (receiverRunning.get()) {
            return mapOf("ok" to true, "message" to "Receiver already running.")
        }

        receiverRunning.set(true)

        discoveryResponderThread = Thread {
            runDiscoveryResponderLoop()
        }.apply {
            name = "p2p-discovery-responder"
            isDaemon = true
            start()
        }

        receiverThread = Thread {
            try {
                tcpServerSocket = ServerSocket(TCP_PORT)
                while (receiverRunning.get()) {
                    val socket = try {
                        tcpServerSocket?.accept()
                    } catch (_: Throwable) {
                        null
                    } ?: continue

                    try {
                        receiveBundle(socket)
                    } finally {
                        runCatching { socket.close() }
                    }
                }
            } catch (e: Throwable) {
                if (receiverRunning.get()) {
                    lastTransferError = e.message ?: "Receiver failed"
                }
            } finally {
                receiverRunning.set(false)
                runCatching { tcpServerSocket?.close() }
                tcpServerSocket = null
            }
        }.apply {
            name = "p2p-receiver-thread"
            isDaemon = true
            start()
        }

        return mapOf("ok" to true, "message" to "Receiver started.")
    }

    fun stopReceiver(): Map<String, Any> {
        receiverRunning.set(false)
        val runningThread = receiverThread
        val discoveryThread = discoveryResponderThread
        receiverThread = null
        discoveryResponderThread = null
        runCatching { runningThread?.interrupt() }
        runCatching { discoveryThread?.interrupt() }
        runCatching { tcpServerSocket?.close() }
        runCatching { udpResponderSocket?.close() }
        tcpServerSocket = null
        udpResponderSocket = null
        return mapOf("ok" to true, "message" to "Receiver stopped.")
    }

    fun sendBundle(targetAddress: String, filePath: String): Map<String, Any> {
        val resolvedAddress = if (isIpv4Address(targetAddress)) {
            targetAddress
        } else {
            resolveWifiDirectRoute(targetAddress)
        }

        if (resolvedAddress == null || !isIpv4Address(resolvedAddress)) {
            return mapOf(
                "ok" to false,
                "message" to "Unable to resolve Wi-Fi Direct route to peer. Ensure peer is reachable and receiver is running.",
            )
        }

        val file = File(filePath)
        if (!file.exists() || !file.isFile) {
            return mapOf("ok" to false, "message" to "Bundle file not found.")
        }
        if (file.length() <= 0L || file.length() > MAX_BUNDLE_BYTES) {
            return mapOf("ok" to false, "message" to "Bundle file size is invalid.")
        }

        var socket: Socket? = null
        val startedAt = System.currentTimeMillis()
        sendTelemetry = TransferTelemetry(
            direction = "send",
            stage = "connecting",
            peerAddress = resolvedAddress,
            fileName = file.name,
            totalBytes = file.length(),
            transferredBytes = 0L,
            startedAtMs = startedAt,
            updatedAtMs = startedAt,
            done = false,
            success = false,
            errorMessage = "",
        )

        return try {
            socket = Socket(resolvedAddress, TCP_PORT)
            socket.soTimeout = 15_000

            sendTelemetry = sendTelemetry?.copy(
                stage = "sending",
                updatedAtMs = System.currentTimeMillis(),
            )

            DataOutputStream(BufferedOutputStream(socket.outputStream)).use { out ->
                out.writeUTF(file.name)
                out.writeLong(file.length())

                FileInputStream(file).use { fis ->
                    val buffer = ByteArray(16 * 1024)
                    var transferred = 0L
                    while (true) {
                        val read = fis.read(buffer)
                        if (read <= 0) break
                        out.write(buffer, 0, read)
                        transferred += read.toLong()
                        sendTelemetry = sendTelemetry?.copy(
                            transferredBytes = transferred,
                            updatedAtMs = System.currentTimeMillis(),
                        )
                    }
                }

                out.flush()
            }

            sendTelemetry = sendTelemetry?.copy(
                stage = "completed",
                transferredBytes = file.length(),
                updatedAtMs = System.currentTimeMillis(),
                done = true,
                success = true,
                errorMessage = "",
            )

            mapOf("ok" to true, "message" to "Bundle sent successfully.", "bytes" to file.length())
        } catch (e: Throwable) {
            lastTransferError = e.message ?: "Send failed"
            sendTelemetry = sendTelemetry?.copy(
                stage = "failed",
                updatedAtMs = System.currentTimeMillis(),
                done = true,
                success = false,
                errorMessage = lastTransferError,
            )
            mapOf("ok" to false, "message" to lastTransferError)
        } finally {
            runCatching { socket?.close() }
        }
    }

    fun listReceivedBundles(): List<Map<String, Any>> {
        val inbox = inboxDir()
        if (!inbox.exists() || !inbox.isDirectory) {
            return emptyList()
        }

        return inbox.listFiles()
            ?.filter { it.isFile }
            ?.sortedByDescending { it.lastModified() }
            ?.map { file ->
                mapOf(
                    "name" to file.name,
                    "path" to file.absolutePath,
                    "sizeBytes" to file.length(),
                    "lastModified" to file.lastModified(),
                )
            }
            ?: emptyList()
    }

    fun listPendingIncomingTransfers(): List<Map<String, Any>> {
        return pendingIncomingTransfers.values
            .sortedByDescending { it.createdAt }
            .map { pending ->
                mapOf(
                    "id" to pending.id,
                    "senderAddress" to pending.senderAddress,
                    "fileName" to pending.fileName,
                    "sizeBytes" to pending.sizeBytes,
                    "createdAt" to pending.createdAt,
                )
            }
    }

    fun getTransferTelemetry(): Map<String, Any> {
        return mapOf(
            "send" to (sendTelemetry?.toMap() ?: emptyMap<String, Any>()),
            "receive" to (receiveTelemetry?.toMap() ?: emptyMap<String, Any>()),
        )
    }

    fun approveIncomingTransfer(id: String): Map<String, Any> {
        val pending = pendingIncomingTransfers[id]
            ?: return mapOf("ok" to false, "message" to "Pending transfer not found.")
        pending.approved = true
        pending.decisionLatch.countDown()
        return mapOf("ok" to true, "message" to "Incoming transfer approved.")
    }

    fun rejectIncomingTransfer(id: String): Map<String, Any> {
        val pending = pendingIncomingTransfers[id]
            ?: return mapOf("ok" to false, "message" to "Pending transfer not found.")
        pending.approved = false
        pending.decisionLatch.countDown()
        return mapOf("ok" to true, "message" to "Incoming transfer rejected.")
    }

    private fun receiveBundle(socket: Socket) {
        socket.soTimeout = RECEIVE_APPROVAL_TIMEOUT_MS.toInt()
        DataInputStream(BufferedInputStream(socket.inputStream)).use { input ->
            val fileName = input.readUTF().takeIf { it.isNotBlank() } ?: "bundle.json"
            val size = input.readLong()
            if (size <= 0 || size > MAX_BUNDLE_BYTES) {
                throw IllegalStateException("Invalid incoming bundle size: $size")
            }

            val pending = PendingIncomingTransfer(
                id = UUID.randomUUID().toString(),
                senderAddress = socket.inetAddress?.hostAddress.orEmpty(),
                fileName = sanitizeFileName(fileName),
                sizeBytes = size,
                createdAt = System.currentTimeMillis(),
            )

            val startedAt = System.currentTimeMillis()
            receiveTelemetry = TransferTelemetry(
                direction = "receive",
                stage = "awaiting-approval",
                peerAddress = pending.senderAddress,
                fileName = pending.fileName,
                totalBytes = size,
                transferredBytes = 0L,
                startedAtMs = startedAt,
                updatedAtMs = startedAt,
                done = false,
                success = false,
                errorMessage = "",
            )

            pendingIncomingTransfers[pending.id] = pending

            val approved = try {
                pending.decisionLatch.await(RECEIVE_APPROVAL_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                pending.approved == true
            } finally {
                pendingIncomingTransfers.remove(pending.id)
            }

            if (!approved) {
                lastTransferError = "Incoming transfer rejected or timed out: ${pending.fileName}"
                receiveTelemetry = receiveTelemetry?.copy(
                    stage = "rejected",
                    updatedAtMs = System.currentTimeMillis(),
                    done = true,
                    success = false,
                    errorMessage = lastTransferError,
                )
                throw IllegalStateException("Incoming transfer not approved")
            }

            receiveTelemetry = receiveTelemetry?.copy(
                stage = "receiving",
                updatedAtMs = System.currentTimeMillis(),
            )

            val target = File(inboxDir(), "${System.currentTimeMillis()}_${pending.fileName}")
            FileOutputStream(target).use { fos ->
                val out = BufferedOutputStream(fos)
                val buffer = ByteArray(16 * 1024)
                var remaining = size
                var transferred = 0L

                while (remaining > 0) {
                    val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                    if (read <= 0) {
                        receiveTelemetry = receiveTelemetry?.copy(
                            stage = "failed",
                            updatedAtMs = System.currentTimeMillis(),
                            done = true,
                            success = false,
                            errorMessage = "Connection ended before transfer completed.",
                        )
                        throw IllegalStateException("Connection ended before transfer completed.")
                    }
                    out.write(buffer, 0, read)
                    remaining -= read.toLong()
                    transferred += read.toLong()
                    receiveTelemetry = receiveTelemetry?.copy(
                        transferredBytes = transferred,
                        updatedAtMs = System.currentTimeMillis(),
                    )
                }

                out.flush()
            }

            receiveTelemetry = receiveTelemetry?.copy(
                stage = "completed",
                transferredBytes = size,
                updatedAtMs = System.currentTimeMillis(),
                done = true,
                success = true,
                errorMessage = "",
            )
        }
    }

    private fun runDiscoveryResponderLoop() {
        try {
            udpResponderSocket = DatagramSocket(UDP_PORT).apply {
                broadcast = true
                soTimeout = 1000
            }

            val buffer = ByteArray(512)
            while (receiverRunning.get()) {
                try {
                    val packet = DatagramPacket(buffer, buffer.size)
                    udpResponderSocket?.receive(packet)
                    val msg = String(packet.data, 0, packet.length)
                    if (msg != DISCOVERY_PROBE) {
                        continue
                    }

                    val localIp = getLocalIpv4Address().orEmpty()
                    if (localIp.isEmpty()) {
                        continue
                    }

                    val responseText = "$DISCOVERY_REPLY_PREFIX:${Build.MODEL}:$localIp:$TCP_PORT"
                    val replyBytes = responseText.toByteArray()
                    val reply = DatagramPacket(
                        replyBytes,
                        replyBytes.size,
                        packet.address,
                        packet.port,
                    )
                    udpResponderSocket?.send(reply)
                } catch (_: SocketTimeoutException) {
                    // Keep loop alive while running.
                }
            }
        } catch (e: Throwable) {
            if (receiverRunning.get()) {
                lastTransferError = e.message ?: "Discovery responder failed"
            }
        } finally {
            runCatching { udpResponderSocket?.close() }
            udpResponderSocket = null
        }
    }

    private fun discoverPeersOnWifiDirect(): List<Map<String, String>> {
        if (!hasWifiDirectRuntimePermissions()) {
            lastTransferError = "Wi-Fi Direct requires runtime Nearby Wi-Fi and Location permissions."
            return emptyList()
        }

        val manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
            ?: return emptyList()
        val channel = manager.initialize(context, Looper.getMainLooper(), null)
            ?: return emptyList()

        val latch = CountDownLatch(1)
        val results = linkedMapOf<String, Map<String, String>>()

        manager.discoverPeers(
            channel,
            object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    Handler(Looper.getMainLooper()).postDelayed({
                        manager.requestPeers(channel) { peerList ->
                            for (device in peerList.deviceList) {
                                addWifiDirectPeer(results, device)
                            }
                            latch.countDown()
                        }
                    }, 900L)
                }

                override fun onFailure(reason: Int) {
                    lastTransferError = "Wi-Fi Direct discovery failed (reason=$reason)."
                    latch.countDown()
                }
            },
        )

        latch.await(WIFI_DIRECT_DISCOVERY_WAIT_MS, TimeUnit.MILLISECONDS)
        return results.values.toList().sortedBy { it["name"] }
    }

    private fun addWifiDirectPeer(
        store: MutableMap<String, Map<String, String>>,
        device: WifiP2pDevice,
    ) {
        val address = device.deviceAddress.orEmpty()
        if (address.isBlank()) {
            return
        }

        val peerName = device.deviceName?.takeIf { it.isNotBlank() } ?: "Wi-Fi Direct Device"
        val resolved = wifiDirectResolvedRoutes[address.lowercase(Locale.US)]
        store[address] = mapOf(
            "name" to peerName,
            "address" to address,
            "transport" to "wifi-direct",
            "resolvedAddress" to (resolved ?: ""),
        )
    }

    private fun resolveWifiDirectRoute(deviceAddress: String): String? {
        val normalized = deviceAddress.lowercase(Locale.US)
        wifiDirectResolvedRoutes[normalized]?.let { cached ->
            if (isIpv4Address(cached)) {
                return cached
            }
        }

        if (!hasWifiDirectRuntimePermissions()) {
            lastTransferError = "Wi-Fi Direct permissions are missing."
            return null
        }

        val manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
            ?: return null
        val channel = manager.initialize(context, Looper.getMainLooper(), null)
            ?: return null

        val connectLatch = CountDownLatch(1)
        var actionOk = false
        val config = WifiP2pConfig().apply {
            this.deviceAddress = deviceAddress
        }

        manager.connect(
            channel,
            config,
            object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    actionOk = true
                    connectLatch.countDown()
                }

                override fun onFailure(reason: Int) {
                    lastTransferError = "Wi-Fi Direct connect failed (reason=$reason)."
                    connectLatch.countDown()
                }
            },
        )

        connectLatch.await(4, TimeUnit.SECONDS)
        if (!actionOk) {
            return null
        }

        val infoLatch = CountDownLatch(1)
        var connectionInfo: WifiP2pInfo? = null
        var groupInfo: WifiP2pGroup? = null

        Handler(Looper.getMainLooper()).postDelayed({
            manager.requestConnectionInfo(channel) { info ->
                connectionInfo = info
                infoLatch.countDown()
            }
            manager.requestGroupInfo(channel) { group ->
                groupInfo = group
            }
        }, 900L)

        infoLatch.await(4, TimeUnit.SECONDS)
        val info = connectionInfo ?: return null
        if (!info.groupFormed) {
            lastTransferError = "Wi-Fi Direct group not formed yet."
            return null
        }

        val resolved = if (!info.isGroupOwner) {
            info.groupOwnerAddress?.hostAddress
        } else {
            val targetMac = normalized
            resolvePeerIpFromArp(targetMac) ?: resolveClientIpFromGroup(groupInfo)
        }

        if (resolved != null && isIpv4Address(resolved)) {
            wifiDirectResolvedRoutes[normalized] = resolved
            return resolved
        }

        lastTransferError = "Wi-Fi Direct route resolved but no peer IPv4 target was found."
        return null
    }

    private fun resolveClientIpFromGroup(groupInfo: WifiP2pGroup?): String? {
        val group = groupInfo ?: return null
        val ownerMac = group.owner?.deviceAddress?.lowercase(Locale.US)
        val clients = group.clientList
        for (client in clients) {
            val clientMac = client.deviceAddress?.lowercase(Locale.US) ?: continue
            if (ownerMac != null && clientMac == ownerMac) {
                continue
            }
            val ip = resolvePeerIpFromArp(clientMac)
            if (ip != null) {
                return ip
            }
        }
        return null
    }

    private fun resolvePeerIpFromArp(targetMac: String): String? {
        val normalizedMac = targetMac.lowercase(Locale.US)
        return runCatching {
            FileReader("/proc/net/arp").use { reader ->
                reader.readLines().drop(1).forEach { line ->
                    val cols = line.trim().split(Regex("\\s+"))
                    if (cols.size < 4) {
                        return@forEach
                    }
                    val ip = cols[0]
                    val mac = cols[3].lowercase(Locale.US)
                    if (mac == normalizedMac && isIpv4Address(ip)) {
                        return ip
                    }
                }
            }
            null
        }.getOrNull()
    }

    private fun hasWifiDirectRuntimePermissions(): Boolean {
        val locationGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED

        val nearbyGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.NEARBY_WIFI_DEVICES,
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

        return locationGranted && nearbyGranted
    }

    private fun discoverPeersOnLan(): List<Map<String, String>> {
        val localIp = getLocalIpv4Address() ?: return emptyList()
        val results = linkedMapOf<String, Map<String, String>>()

        val socket = DatagramSocket().apply {
            broadcast = true
            soTimeout = 800
        }

        try {
            val probeBytes = DISCOVERY_PROBE.toByteArray()
            for (addr in getBroadcastAddresses()) {
                val packet = DatagramPacket(probeBytes, probeBytes.size, addr, UDP_PORT)
                runCatching { socket.send(packet) }
            }

            val endAt = System.currentTimeMillis() + 1200
            val recvBuf = ByteArray(512)
            while (System.currentTimeMillis() < endAt) {
                try {
                    val packet = DatagramPacket(recvBuf, recvBuf.size)
                    socket.receive(packet)
                    val text = String(packet.data, 0, packet.length)
                    if (!text.startsWith("$DISCOVERY_REPLY_PREFIX:")) {
                        continue
                    }

                    val parts = text.split(':')
                    if (parts.size < 4) {
                        continue
                    }

                    val name = parts[1]
                    val ip = parts[2]
                    if (ip == localIp) {
                        continue
                    }

                    results[ip] = mapOf(
                        "name" to name,
                        "address" to ip,
                        "transport" to "wifi-lan",
                    )
                } catch (_: SocketTimeoutException) {
                    break
                }
            }
        } catch (e: Throwable) {
            lastTransferError = e.message ?: "Peer discovery failed"
        } finally {
            runCatching { socket.close() }
        }

        return results.values.toList().sortedBy { it["name"] }
    }

    private fun inboxDir(): File {
        val inbox = File(context.filesDir, "p2p_inbox")
        if (!inbox.exists()) {
            inbox.mkdirs()
        }
        return inbox
    }

    private fun sanitizeFileName(name: String): String {
        return name.replace(Regex("[^a-zA-Z0-9._-]"), "_")
    }

    private fun isIpv4Address(value: String): Boolean {
        val parts = value.split('.')
        if (parts.size != 4) {
            return false
        }
        return parts.all { part ->
            val num = part.toIntOrNull() ?: return@all false
            num in 0..255
        }
    }

    private fun getLocalIpv4Address(): String? {
        val interfaces = NetworkInterface.getNetworkInterfaces()?.toList() ?: return null
        for (iface in interfaces) {
            if (!iface.isUp || iface.isLoopback) {
                continue
            }
            for (addr in iface.inetAddresses) {
                if (addr is Inet4Address && !addr.isLoopbackAddress) {
                    return addr.hostAddress
                }
            }
        }
        return null
    }

    private fun getBroadcastAddresses(): List<InetAddress> {
        val addrs = mutableListOf<InetAddress>()
        val interfaces = NetworkInterface.getNetworkInterfaces()?.toList() ?: return listOf(
            InetAddress.getByName("255.255.255.255"),
        )

        for (iface in interfaces) {
            if (!iface.isUp || iface.isLoopback) {
                continue
            }
            for (intfAddr in iface.interfaceAddresses) {
                val broadcast = intfAddr.broadcast
                if (broadcast != null) {
                    addrs.add(broadcast)
                }
            }
        }

        if (addrs.isEmpty()) {
            addrs.add(InetAddress.getByName("255.255.255.255"))
        }
        return addrs
    }
}
