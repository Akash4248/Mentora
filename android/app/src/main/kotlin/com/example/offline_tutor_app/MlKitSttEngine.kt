package com.example.offline_tutor_app

import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Log
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.audio.AudioSource
import com.google.mlkit.genai.speechrecognition.SpeechRecognition
import com.google.mlkit.genai.speechrecognition.SpeechRecognizer
import com.google.mlkit.genai.speechrecognition.SpeechRecognizerOptions
import com.google.mlkit.genai.speechrecognition.SpeechRecognizerResponse
import com.google.mlkit.genai.speechrecognition.speechRecognizerOptions
import com.google.mlkit.genai.speechrecognition.speechRecognizerRequest
import java.io.File
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

class MlKitSttException(
    val code: String,
    override val message: String,
) : Exception(message)

class MlKitSttEngine {
    suspend fun isAvailable(languageCode: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        if (!isLanguageSupported(languageCode)) return false

        val recognizer = createRecognizer(languageCode)
        return try {
            val status = recognizer.checkStatus()
            status == FeatureStatus.AVAILABLE || status == FeatureStatus.DOWNLOADABLE
        } catch (_: Throwable) {
            false
        } finally {
            recognizer.close()
        }
    }

    suspend fun transcribe(wavFile: File, languageCode: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            throw MlKitSttException(
                "STT_UNSUPPORTED_DEVICE",
                "ML Kit GenAI speech recognition requires Android 12 (API 31) or newer.",
            )
        }
        if (!isLanguageSupported(languageCode)) {
            throw MlKitSttException(
                "STT_LANGUAGE_UNSUPPORTED",
                "ML Kit GenAI speech recognition supports English and Hindi. Kannada is not supported.",
            )
        }

        val pcm = withContext(Dispatchers.IO) { readWavPcm(wavFile) }
        if (pcm.bytes.isEmpty()) return ""
        if (pcm.sampleRate != SAMPLE_RATE || pcm.channels != 1 || pcm.bitsPerSample != 16) {
            throw MlKitSttException(
                "STT_AUDIO_FORMAT",
                "Expected 16 kHz mono 16-bit PCM audio.",
            )
        }

        val recognizer = createRecognizer(languageCode)
        try {
            val status = ensureReady(recognizer)
            if (status != FeatureStatus.AVAILABLE) {
                throw MlKitSttException("STT_NOT_AVAILABLE", statusMessage(status))
            }
            return recognize(recognizer, pcm)
        } finally {
            recognizer.close()
        }
    }

    private suspend fun recognize(recognizer: SpeechRecognizer, pcm: PcmAudio): String =
        coroutineScope {
            val pipe = ParcelFileDescriptor.createPipe()
            val readPipe = pipe[0]
            val done = CompletableDeferred<Outcome>()
            val transcript = StringBuilder()

            val writer = launch(Dispatchers.IO) {
                try {
                    feedPcm(pipe[1], pcm)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    if (!done.isCompleted) {
                        done.complete(Outcome.Failure("Audio feed failed: ${e.message}"))
                    }
                }
            }

            val collector = launch {
                try {
                    recognizer.startRecognition(
                        speechRecognizerRequest {
                            audioSource = AudioSource.fromPfd(readPipe)
                        },
                    ).collect { response ->
                        when (response) {
                            is SpeechRecognizerResponse.PartialTextResponse -> Unit
                            is SpeechRecognizerResponse.FinalTextResponse -> {
                                transcript.append(response.text)
                            }
                            is SpeechRecognizerResponse.CompletedResponse -> {
                                if (!done.isCompleted) {
                                    done.complete(Outcome.Success(transcript.toString()))
                                }
                            }
                            is SpeechRecognizerResponse.ErrorResponse -> {
                                if (!done.isCompleted) {
                                    done.complete(
                                        Outcome.Failure(
                                            "${response.e.errorCode}: ${response.e.message}",
                                        ),
                                    )
                                }
                            }
                        }
                    }
                    if (!done.isCompleted) {
                        done.complete(Outcome.Success(transcript.toString()))
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    if (!done.isCompleted) {
                        done.complete(Outcome.Failure(e.message ?: "Speech recognition failed."))
                    }
                }
            }

            val bytesPerSecond = pcm.sampleRate * pcm.channels * (pcm.bitsPerSample / 8)
            val durationMs =
                pcm.bytes.size.toLong() * 1000L / bytesPerSecond.toLong()
            val timeoutMs = maxOf(30_000L, durationMs + 30_000L)

            val outcome = try {
                withTimeoutOrNull(timeoutMs) { done.await() }
            } finally {
                writer.cancel()
                collector.cancel()
                try {
                    readPipe.close()
                } catch (_: Throwable) {
                }
                try {
                    recognizer.stopRecognition()
                } catch (_: Throwable) {
                }
            }

            when (outcome) {
                null -> throw MlKitSttException("STT_TIMEOUT", "Speech recognition timed out.")
                is Outcome.Failure -> throw MlKitSttException("STT_FAILED", outcome.message)
                is Outcome.Success -> outcome.text.trim()
            }
        }

    private suspend fun ensureReady(recognizer: SpeechRecognizer): Int {
        var status = recognizer.checkStatus()
        if (status == FeatureStatus.DOWNLOADABLE) {
            try {
                recognizer.download().collect { downloadStatus ->
                    when (downloadStatus) {
                        is DownloadStatus.DownloadStarted ->
                            Log.i(
                                TAG,
                                "STT download started: ${downloadStatus.bytesToDownload} bytes",
                            )
                        is DownloadStatus.DownloadProgress -> Unit
                        is DownloadStatus.DownloadCompleted ->
                            Log.i(TAG, "STT download completed")
                        is DownloadStatus.DownloadFailed ->
                            Log.e(TAG, "STT download failed", downloadStatus.e)
                    }
                }
            } catch (e: Throwable) {
                Log.e(TAG, "STT download failed", e)
            }
            status = recognizer.checkStatus()
        }
        return status
    }

    private fun createRecognizer(languageCode: String): SpeechRecognizer =
        SpeechRecognition.getClient(
            speechRecognizerOptions {
                locale = localeFor(languageCode)
                preferredMode = SpeechRecognizerOptions.Mode.MODE_BASIC
            },
        )

    private fun localeFor(languageCode: String): Locale {
        val normalized = languageCode.trim().lowercase().replace('_', '-')
        val base = normalized.substringBefore('-')
        val tag = when {
            base == "en" -> "en-US"
            base == "hi" -> "hi-IN"
            normalized.contains('-') -> normalized
            else -> "en-US"
        }
        return Locale.forLanguageTag(tag)
    }

    private fun isLanguageSupported(languageCode: String): Boolean {
        val base = languageCode.trim().lowercase().substringBefore('-').substringBefore('_')
        return base == "en" || base == "hi"
    }

    private fun statusMessage(status: Int): String = when (status) {
        FeatureStatus.DOWNLOADABLE -> "The speech model must be downloaded before first use."
        FeatureStatus.DOWNLOADING -> "The speech model is still downloading."
        FeatureStatus.UNAVAILABLE -> "Speech recognition is unavailable for this device or language."
        else -> "Speech recognition is not available."
    }

    private suspend fun feedPcm(
        pfd: ParcelFileDescriptor,
        pcm: PcmAudio,
    ) {
        val bytesPerSecond = pcm.sampleRate * pcm.channels * (pcm.bitsPerSample / 8)
        if (bytesPerSecond <= 0) return
        val chunkBytes = maxOf(bytesPerSecond / 10, 320)
        val startNs = SystemClock.elapsedRealtimeNanos()

        ParcelFileDescriptor.AutoCloseOutputStream(pfd).use { output ->
            var offset = 0
            while (offset < pcm.bytes.size) {
                val end = minOf(offset + chunkBytes, pcm.bytes.size)
                output.write(pcm.bytes, offset, end - offset)
                output.flush()
                offset = end

                val targetNs =
                    startNs + offset.toLong() * 1_000_000_000L / bytesPerSecond.toLong()
                val sleepMs = (targetNs - SystemClock.elapsedRealtimeNanos()) / 1_000_000L
                if (sleepMs > 0) delay(sleepMs)
            }
        }
    }

    private fun readWavPcm(file: File): PcmAudio {
        val bytes = file.readBytes()
        if (
            bytes.size < 12 ||
            String(bytes, 0, 4, Charsets.US_ASCII) != "RIFF" ||
            String(bytes, 8, 4, Charsets.US_ASCII) != "WAVE"
        ) {
            return PcmAudio(bytes, SAMPLE_RATE, 1, 16)
        }

        var offset = 12
        var sampleRate = 0
        var channels = 0
        var bitsPerSample = 0
        var dataOffset = -1
        var dataLength = 0

        while (offset + 8 <= bytes.size) {
            val chunkId = String(bytes, offset, 4, Charsets.US_ASCII)
            val chunkSize = readIntLe(bytes, offset + 4)
            val chunkBody = offset + 8
            if (chunkSize < 0 || chunkBody > bytes.size) break

            when (chunkId) {
                "fmt " -> {
                    if (chunkSize >= 16 && chunkBody + 16 <= bytes.size) {
                        channels = readShortLe(bytes, chunkBody + 2)
                        sampleRate = readIntLe(bytes, chunkBody + 4)
                        bitsPerSample = readShortLe(bytes, chunkBody + 14)
                    }
                }
                "data" -> {
                    dataOffset = chunkBody
                    dataLength = minOf(chunkSize, bytes.size - chunkBody)
                    break
                }
            }

            offset = chunkBody + chunkSize + (chunkSize and 1)
        }

        if (dataOffset < 0 || dataLength <= 0) {
            return PcmAudio(ByteArray(0), sampleRate, channels, bitsPerSample)
        }
        return PcmAudio(
            bytes.copyOfRange(dataOffset, dataOffset + dataLength),
            sampleRate,
            channels,
            bitsPerSample,
        )
    }

    private fun readIntLe(bytes: ByteArray, offset: Int): Int =
        (bytes[offset].toInt() and 0xFF) or
            ((bytes[offset + 1].toInt() and 0xFF) shl 8) or
            ((bytes[offset + 2].toInt() and 0xFF) shl 16) or
            ((bytes[offset + 3].toInt() and 0xFF) shl 24)

    private fun readShortLe(bytes: ByteArray, offset: Int): Int =
        (bytes[offset].toInt() and 0xFF) or
            ((bytes[offset + 1].toInt() and 0xFF) shl 8)

    private sealed interface Outcome {
        data class Success(val text: String) : Outcome
        data class Failure(val message: String) : Outcome
    }

    private data class PcmAudio(
        val bytes: ByteArray,
        val sampleRate: Int,
        val channels: Int,
        val bitsPerSample: Int,
    )

    companion object {
        private const val TAG = "MentoraStt"
        private const val SAMPLE_RATE = 16_000
    }
}
