import 'dart:io';
import '../../../core/theme/idp_colors.dart';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../course/data/local/course_repository.dart';
import '../../content_packs/application/content_pack_bootstrap_service.dart';
import '../../content_packs/application/content_pack_policy_service.dart';
import '../../content_packs/data/local/content_pack_repository.dart';
import '../../content_packs/domain/content_pack_models.dart';
import '../../content_packs/presentation/content_pack_installer_screen.dart';
import '../../p2p/data/p2p_channel_service.dart';
import '../data/local/media_resource_repository.dart';
import '../data/local/study_note_repository.dart';
import 'pdf_viewer_screen.dart';
import 'video_player_screen.dart';


const List<String> _androidTextbookRootCandidates = <String>[
  '/storage/emulated/0/TEXTBOOKS',
  '/storage/emulated/0/textbooks',
  '/sdcard/TEXTBOOKS',
  '/sdcard/textbooks',
  '/storage/emulated/0/Download/TEXTBOOKS',
  '/storage/emulated/0/Download/textbooks',
];
const List<String> _androidVideoRootCandidates = <String>[
  '/storage/emulated/0/VIDEOS',
  '/storage/emulated/0/videos',
  '/sdcard/VIDEOS',
  '/sdcard/videos',
  '/storage/emulated/0/Download/VIDEOS',
  '/storage/emulated/0/Download/videos',
];

/// Screen to browse, import, and share learning materials.
class LearningMaterialsScreen extends StatefulWidget {
  const LearningMaterialsScreen({
    required this.courseRepository,
    super.key,
  });

  final CourseRepository courseRepository;

  @override
  State<LearningMaterialsScreen> createState() => _LearningMaterialsScreenState();
}

class _LearningMaterialsScreenState extends State<LearningMaterialsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final MediaResourceRepository _mediaRepository = MediaResourceRepository();
  final StudyNoteRepository _noteRepository = StudyNoteRepository();
  final ContentPackBootstrapService _packBootstrapService =
      ContentPackBootstrapService();
    final ContentPackPolicyService _packPolicyService =
      const ContentPackPolicyService();
  final ContentPackRepository _packRepository = ContentPackRepository();
  final P2PChannelService _p2pService = P2PChannelService();

  bool _loading = true;
  bool _importingP2PResources = false;

  List<MediaResource> _textbooks = const <MediaResource>[];
  List<MediaResource> _videos = const <MediaResource>[];
  List<MediaResource> _resources = const <MediaResource>[];
  List<StudyNote> _notes = const <StudyNote>[];
  List<ContentPackCatalogEntry> _packs = const <ContentPackCatalogEntry>[];
  ContentPackReadinessReport? _readiness;

  final List<_MaterialType> _materialTypes = [
    _MaterialType(
      label: 'Textbooks',
      icon: Icons.book_rounded,
      color: Color(0xFF0B6E4F),
      description: 'PDF textbooks and study guides',
    ),
    _MaterialType(
      label: 'Videos',
      icon: Icons.videocam_rounded,
      color: Color(0xFF6366F1),
      description: 'Educational video lectures',
    ),
    _MaterialType(
      label: 'Resources',
      icon: Icons.folder_rounded,
      color: Color(0xFFFF6B35),
      description: 'Supplementary materials',
    ),
    _MaterialType(
      label: 'Notes',
      icon: Icons.note_rounded,
      color: Color(0xFF10B981),
      description: 'Study notes and summaries',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _materialTypes.length, vsync: this);
    _loadResources();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadResources() async {
    setState(() {
      _loading = true;
    });

    await _syncRepoMediaToDb();

    await _packBootstrapService.bootstrapLegacyMediaIntoPacks();

    final textbookItems = await _packRepository.listItemsByKind('pdf');
    final videoItems = await _packRepository.listItemsByKind('video');
    final resourceItems = <ContentPackItem>[
      ...await _packRepository.listItemsByKind('resource'),
      ...await _packRepository.listItemsByKind('quiz'),
      ...await _packRepository.listItemsByKind('other'),
    ];

    final textbooks = textbookItems
        .map((item) => _resourceFromPackItem(item, mediaType: 'textbook'))
        .toList();
    final videos = videoItems
        .map((item) => _resourceFromPackItem(item, mediaType: 'video'))
        .toList();
    final resources = resourceItems
        .map((item) => _resourceFromPackItem(item, mediaType: 'resource'))
        .toList();
    final notes = await _noteRepository.listAll();
    final packEntries = <ContentPackCatalogEntry>[];
    final installedManifests = await _packRepository.listInstalledPacks();
    for (final manifest in installedManifests) {
      try {
        packEntries.add(await _packRepository.buildCatalogEntry(manifest.packId));
      } catch (_) {
        // Skip broken pack rows and continue loading the rest.
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _textbooks = textbooks;
      _videos = videos;
      _resources = resources;
      _notes = notes;
      _packs = packEntries;
      _readiness = _packPolicyService.evaluate(
        installedPacks: installedManifests,
      );
      _loading = false;
    });
  }

  MediaResource _resourceFromPackItem(
    ContentPackItem item, {
    required String mediaType,
  }) {
    return MediaResource(
      mediaType: mediaType,
      title: item.title,
      localPath: item.absolutePath,
      sourcePath: item.relativePath,
      sizeBytes: item.sizeBytes,
      importedAt: 0,
    );
  }

  Future<void> _importResourcesFromP2PInbox() async {
    setState(() {
      _importingP2PResources = true;
    });

    try {
      final inboxFiles = await _p2pService.listReceivedBundles();
      final existingSources = _resources
          .map((item) => item.sourcePath)
          .whereType<String>()
          .toSet();

      if (inboxFiles.isEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('P2P inbox is empty. Receive files from Community Learning first.')),
        );
        return;
      }

      final imported = <MediaResource>[];
      for (final entry in inboxFiles) {
        final sourcePath = entry.path;
        if (sourcePath.isEmpty || existingSources.contains(sourcePath)) {
          continue;
        }
        final sourceFile = File(sourcePath);
        if (!await sourceFile.exists()) {
          continue;
        }

        final copied = await _copyIntoAppStorage(
          sourcePath: sourcePath,
          mediaType: 'resource',
        );
        imported.add(copied);
      }

      if (imported.isNotEmpty) {
        await _mediaRepository.upsertMany(imported);
      }
      await _loadResources();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${imported.length} shared resources from P2P inbox.')),
      );
    } on MissingPluginException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('P2P inbox import is available on Android builds.')),
      );
    } on PlatformException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'P2P inbox import failed.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('P2P inbox import failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _importingP2PResources = false;
        });
      }
    }
  }

  Future<void> _openNoteEditor({StudyNote? note}) async {
    final titleController = TextEditingController(text: note?.title ?? '');
    final bodyController = TextEditingController(text: note?.body ?? '');

    final action = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(note == null ? 'Add Note' : 'Edit Note'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bodyController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            if (note != null)
              TextButton(
                onPressed: () => Navigator.of(context).pop('delete'),
                child: const Text('Delete'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted || action == null || action == 'cancel') {
      return;
    }

    if (action == 'delete') {
      final noteId = note?.id;
      if (noteId != null) {
        await _noteRepository.delete(noteId);
        await _loadResources();
      }
      return;
    }

    final title = titleController.text.trim();
    final body = bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and note body are required.')),
      );
      return;
    }

    if (note?.id == null) {
      await _noteRepository.create(title: title, body: body);
    } else {
      await _noteRepository.update(id: note!.id!, title: title, body: body);
    }

    await _loadResources();
  }

  Future<void> _deleteNote(StudyNote note) async {
    final noteId = note.id;
    if (noteId == null) {
      return;
    }

    await _noteRepository.delete(noteId);
    await _loadResources();
  }

  Future<void> _syncRepoMediaToDb() async {
    // App-private dirs first (work on iOS/desktop + scoped storage);
    // legacy absolute /storage paths below are Android-only fallbacks.
    final textbookRoots = <String>{};
    final videoRoots = <String>{};
    try {
      final docs = await getApplicationDocumentsDirectory();
      textbookRoots.add(p.join(docs.path, 'content_packs'));
      textbookRoots.add(p.join(docs.path, 'TEXTBOOKS'));
      videoRoots.add(p.join(docs.path, 'VIDEOS'));
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        textbookRoots.add(p.join(ext.path, 'TEXTBOOKS'));
        videoRoots.add(p.join(ext.path, 'VIDEOS'));
      }
    } catch (_) {}
    textbookRoots.addAll(_androidTextbookRootCandidates);
    videoRoots.addAll(_androidVideoRootCandidates);

    if (Platform.isAndroid) {
      textbookRoots.addAll(
        await _discoverAndroidRoots(
          parentRoots: const <String>[
            '/storage/emulated/0',
            '/sdcard',
            '/storage/emulated/0/Download',
          ],
          containsKeyword: 'textbook',
        ),
      );
      videoRoots.addAll(
        await _discoverAndroidRoots(
          parentRoots: const <String>[
            '/storage/emulated/0',
            '/sdcard',
            '/storage/emulated/0/Download',
          ],
          containsKeyword: 'video',
        ),
      );
    }

    final textbooks = await _scanFilesFromRoots(
      rootPaths: textbookRoots.toList(),
      extensions: const <String>{'.pdf'},
      mediaType: 'textbook',
    );
    final videos = await _scanFilesFromRoots(
      rootPaths: videoRoots.toList(),
      extensions: const <String>{'.mp4', '.mkv', '.webm', '.avi'},
      mediaType: 'video',
    );

    await _mediaRepository.upsertMany(<MediaResource>[...textbooks, ...videos]);
  }

  Future<List<String>> _discoverAndroidRoots({
    required List<String> parentRoots,
    required String containsKeyword,
  }) async {
    final matches = <String>[];
    final seen = <String>{};
    final keyword = containsKeyword.toLowerCase();

    for (final parentRoot in parentRoots) {
      final parent = Directory(parentRoot);
      if (!await parent.exists()) {
        continue;
      }
      await for (final entity in parent.list(recursive: false, followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }
        final name = p.basename(entity.path).toLowerCase();
        if (!name.contains(keyword)) {
          continue;
        }
        if (seen.add(entity.path)) {
          matches.add(entity.path);
        }
      }
    }

    return matches;
  }

  Future<List<MediaResource>> _scanFilesFromRoots({
    required List<String> rootPaths,
    required Set<String> extensions,
    required String mediaType,
  }) async {
    final all = <MediaResource>[];
    final seenPaths = <String>{};

    for (final root in rootPaths) {
      final found = await _scanFiles(
        rootPath: root,
        extensions: extensions,
        mediaType: mediaType,
      );
      for (final item in found) {
        if (seenPaths.add(item.localPath)) {
          all.add(item);
        }
      }
    }

    all.sort((a, b) => b.importedAt.compareTo(a.importedAt));
    return all;
  }

  Future<List<MediaResource>> _scanFiles({
    required String rootPath,
    required Set<String> extensions,
    required String mediaType,
  }) async {
    final dir = Directory(rootPath);
    if (!await dir.exists()) {
      return const <MediaResource>[];
    }

    final resources = <MediaResource>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final path = entity.path;
      final lower = path.toLowerCase();
      if (!extensions.any((ext) => lower.endsWith(ext))) {
        continue;
      }
      final stat = await entity.stat();
      resources.add(
        MediaResource(
          mediaType: mediaType,
          title: _displayTitleFromPath(path, rootPath),
          localPath: path,
          sourcePath: path,
          sizeBytes: stat.size,
          importedAt: stat.modified.millisecondsSinceEpoch,
        ),
      );
    }

    return resources;
  }

  String _displayTitleFromPath(String filePath, String rootPath) {
    final normalizedRoot = p.normalize(rootPath);
    final normalizedPath = p.normalize(filePath);
    if (normalizedPath.startsWith(normalizedRoot)) {
      final relative = p.relative(normalizedPath, from: normalizedRoot);
      return relative.replaceAll('\\', '/');
    }
    return p.basename(normalizedPath);
  }

  Future<void> _shareViaP2P(MediaResource resource) async {
    try {
      final peers = await _p2pService.listPeers();
      if (!mounted) {
        return;
      }

      if (peers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No P2P peers discovered. Open P2P screen and refresh peers.')),
        );
        return;
      }

      final selectedPeer = await showDialog<P2PPeer>(
        context: context,
        builder: (context) {
          return SimpleDialog(
            title: const Text('Share via P2P'),
            children: peers
                .map(
                  (peer) => SimpleDialogOption(
                    onPressed: () => Navigator.of(context).pop(peer),
                    child: Text('${peer.name} (${peer.address})'),
                  ),
                )
                .toList(),
          );
        },
      );

      if (selectedPeer == null) {
        return;
      }

      final result = await _p2pService.sendBundle(
        address: selectedPeer.address,
        filePath: resource.localPath,
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } on MissingPluginException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('P2P is not available on this platform yet. Use Android build.')),
      );
    } on PlatformException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'P2P sharing failed.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('P2P sharing failed: $e')),
      );
    }
  }

  Future<void> _openGenericResource(MediaResource resource) async {
    try {
      final file = File(resource.localPath);
      if (!await file.exists()) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Resource not found: ${resource.localPath}')),
        );
        return;
      }

      final result = await OpenFilex.open(resource.localPath);
      if (!mounted) {
        return;
      }
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message.isEmpty ? 'Unable to open this resource.' : result.message)),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open resource: $e')),
      );
    }
  }

  Future<void> _openPdf(MediaResource resource) async {
    try {
      final file = File(resource.localPath);
      if (!await file.exists()) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF not found: ${resource.localPath}')),
        );
        return;
      }

      final result = await OpenFilex.open(resource.localPath);
      if (!mounted) {
        return;
      }
      if (result.type == ResultType.done) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            filePath: resource.localPath,
            title: resource.title,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            filePath: resource.localPath,
            title: resource.title,
          ),
        ),
      );
    }
  }

  Future<MediaResource> _copyIntoAppStorage({
    required String sourcePath,
    required String mediaType,
  }) async {
    final sourceFile = File(sourcePath);
    final docsDir = await getApplicationDocumentsDirectory();
    final subFolder = mediaType == 'video'
        ? 'videos'
        : mediaType == 'textbook'
            ? 'textbooks'
            : 'resources';
    final targetDir = Directory(
      p.join(docsDir.path, 'imported_media', subFolder),
    );
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final baseName = p.basename(sourcePath);
    final targetName = '${DateTime.now().millisecondsSinceEpoch}_$baseName';
    final targetPath = p.join(targetDir.path, targetName);

    final copied = await sourceFile.copy(targetPath);
    final stat = await copied.stat();

    return MediaResource(
      mediaType: mediaType,
      title: p.basename(copied.path),
      localPath: copied.path,
      sourcePath: sourcePath,
      sizeBytes: stat.size,
      importedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Learning Materials'),
        elevation: 0,
        backgroundColor: const Color(0xFF0B6E4F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Manage Content Packs',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ContentPackInstallerScreen(),
                ),
              );
              await _loadResources();
            },
            icon: const Icon(Icons.inventory_2_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadResources,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: const Color(0xFFFF6B35),
          tabs: _materialTypes
              .map(
                (type) => Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(type.icon, size: 20),
                      const SizedBox(width: 8),
                      Text(type.label),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _TextbooksTab(
                  items: _textbooks,
                  packs: _packs,
                  readiness: _readiness,
                  onShare: _shareViaP2P,
                  onOpen: _openPdf,
                ),
                _VideosTab(
                  items: _videos,
                  onShare: _shareViaP2P,
                ),
                _ResourcesTab(
                  items: _resources,
                  importing: _importingP2PResources,
                  onImportFromP2P: _importResourcesFromP2PInbox,
                  onOpen: _openGenericResource,
                  onShare: _shareViaP2P,
                ),
                _NotesTab(
                  notes: _notes,
                  onAdd: () => _openNoteEditor(),
                  onEdit: (note) => _openNoteEditor(note: note),
                  onDelete: _deleteNote,
                ),
              ],
            ),
    );
  }
}

class _MaterialType {
  final String label;
  final IconData icon;
  final Color color;
  final String description;

  _MaterialType({
    required this.label,
    required this.icon,
    required this.color,
    required this.description,
  });
}

class _TextbooksTab extends StatefulWidget {
  const _TextbooksTab({
    required this.items,
    required this.packs,
    required this.readiness,
    required this.onShare,
    required this.onOpen,
  });

  final List<MediaResource> items;
  final List<ContentPackCatalogEntry> packs;
  final ContentPackReadinessReport? readiness;
  final Future<void> Function(MediaResource) onShare;
  final Future<void> Function(MediaResource) onOpen;

  @override
  State<_TextbooksTab> createState() => _TextbooksTabState();
}

class _TextbooksTabState extends State<_TextbooksTab> {
  String _selectedMedium = 'All';
  String _selectedSubject = 'All';
  String _selectedGrade = 'All';
  String? _selectedFolderPath;
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _folderScrollController = ScrollController();
  final ScrollController _pdfScrollController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _folderScrollController.dispose();
    _pdfScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.packs.isEmpty
                    ? 'No offline packs installed yet.'
                    : 'Packs are installed, but textbook rows are not indexed yet.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: const Text('Manage & Sync Content Packs'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: IDPColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.of(context).pushNamed('/content_packs');
                },
              ),
            ],
          ),
        ),
      );
    }

    final taggedItems = widget.items
        .map((item) => _TaggedTextbook(item: item, tag: _classifyTextbook(item)))
        .toList();

    final mediumOptions = <String>{'All'};
    final subjectOptions = <String>{'All'};
    final gradeOptions = <String>{'All'};
    for (final tagged in taggedItems) {
      mediumOptions.add(tagged.tag.medium);
      subjectOptions.add(tagged.tag.subject);
      gradeOptions.add(tagged.tag.gradeLabel);
    }

    final sortedMediumOptions = mediumOptions.toList()..sort();
    final sortedSubjectOptions = subjectOptions.toList()..sort();
    final sortedGradeOptions = gradeOptions.toList()
      ..sort((a, b) {
        if (a == 'All') return -1;
        if (b == 'All') return 1;
        return _gradeSortValue(a).compareTo(_gradeSortValue(b));
      });

    if (!sortedMediumOptions.contains(_selectedMedium)) {
      _selectedMedium = 'All';
    }
    if (!sortedSubjectOptions.contains(_selectedSubject)) {
      _selectedSubject = 'All';
    }
    if (!sortedGradeOptions.contains(_selectedGrade)) {
      _selectedGrade = 'All';
    }

    final filteredItems = taggedItems.where((tagged) {
      final mediumOk = _selectedMedium == 'All' || tagged.tag.medium == _selectedMedium;
      final subjectOk = _selectedSubject == 'All' || tagged.tag.subject == _selectedSubject;
      final gradeOk = _selectedGrade == 'All' || tagged.tag.gradeLabel == _selectedGrade;
      return mediumOk && subjectOk && gradeOk;
    }).toList();

    final folderMap = <String, List<MediaResource>>{};
    for (final tagged in filteredItems) {
      final folderPath = _folderPathFor(tagged.item);
      folderMap.putIfAbsent(folderPath, () => <MediaResource>[]).add(tagged.item);
    }

    final folderEntries = folderMap.entries
        .map((entry) => _FolderEntry(path: entry.key, items: entry.value))
        .toList()
      ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

    if (folderEntries.isNotEmpty) {
      final selectedExists = folderEntries.any((entry) => entry.path == _selectedFolderPath);
      if (!selectedExists) {
        _selectedFolderPath = folderEntries.first.path;
      }
    } else {
      _selectedFolderPath = null;
    }

    final selectedFolderItems = _selectedFolderPath == null
        ? const <MediaResource>[]
        : (folderMap[_selectedFolderPath!] ?? const <MediaResource>[]);

    final query = _searchQuery.trim().toLowerCase();
    final visiblePdfs = selectedFolderItems.where((item) {
      if (query.isEmpty) {
        return true;
      }
      final basis = '${item.title} ${item.sourcePath ?? ''} ${item.localPath}'.toLowerCase();
      return basis.contains(query);
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    final children = <Widget>[
      const _SectionHeader('Offline Textbooks (Grouped)'),
      if (widget.readiness != null)
        Card(
          color: widget.readiness!.isSchoolReady
              ? const Color(0xFFE8F5E9)
              : const Color(0xFFFFF3E0),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.readiness!.isSchoolReady
                      ? 'School Readiness: Ready'
                      : 'School Readiness: Missing Required Packs',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Required coverage: ${widget.readiness!.satisfiedRequiredCount}/${widget.readiness!.requiredCount}',
                ),
                if (widget.readiness!.missingRequiredStatuses.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...widget.readiness!.missingRequiredStatuses.take(4).map(
                    (status) => Text('• ${status.rule.title}'),
                  ),
                ],
              ],
            ),
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedMedium,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Medium',
                        border: OutlineInputBorder(),
                      ),
                      items: sortedMediumOptions
                          .map(
                            (option) => DropdownMenuItem<String>(
                              value: option,
                              child: Text(
                                option,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedMedium = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedSubject,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Subject',
                        border: OutlineInputBorder(),
                      ),
                      items: sortedSubjectOptions
                          .map(
                            (option) => DropdownMenuItem<String>(
                              value: option,
                              child: Text(
                                option,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedSubject = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedGrade,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Grade',
                  border: OutlineInputBorder(),
                ),
                items: sortedGradeOptions
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option,
                        child: Text(
                          option,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedGrade = value;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Search in selected folder',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 780) {
                    return OutlinedButton.icon(
                      onPressed: folderEntries.isEmpty
                          ? null
                          : () => _openFolderPicker(context, folderEntries),
                      icon: const Icon(Icons.folder_open_rounded),
                      label: Text(
                        _selectedFolderPath == null
                            ? 'No folder selected'
                            : 'Folder: ${_displayFolderName(_selectedFolderPath!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }

                  return SizedBox(
                    height: 420,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 240,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Folders',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: Scrollbar(
                                  controller: _folderScrollController,
                                  thumbVisibility: true,
                                  child: ListView.builder(
                                    controller: _folderScrollController,
                                    itemCount: folderEntries.length,
                                    itemBuilder: (context, index) {
                                      final folder = folderEntries[index];
                                      final selected = folder.path == _selectedFolderPath;
                                      return ListTile(
                                        dense: true,
                                        selected: selected,
                                        leading: const Icon(Icons.folder_rounded),
                                        title: Text(
                                          _displayFolderName(folder.path),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text('${folder.items.length} PDFs'),
                                        onTap: () {
                                          setState(() {
                                            _selectedFolderPath = folder.path;
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const VerticalDivider(width: 16),
                        Expanded(
                          child: _PdfListPanel(
                            scrollController: _pdfScrollController,
                            title: _selectedFolderPath == null
                                ? 'No folder selected'
                                : _displayFolderName(_selectedFolderPath!),
                            items: visiblePdfs,
                            onShare: widget.onShare,
                            onOpen: widget.onOpen,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      if (widget.packs.isNotEmpty) ...[
        const SizedBox(height: 4),
        const Text(
          'Installed Packs',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...widget.packs.map(
          (pack) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.inventory_2_rounded),
              title: Text(pack.manifest.title),
              subtitle: Text(
                '${pack.manifest.gradeMin}-${pack.manifest.gradeMax} • ${pack.manifest.medium} • ${pack.itemCount} items',
              ),
            ),
          ),
        ),
      ],
    ];

    if (filteredItems.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text('No textbooks match the selected filters.'),
        ),
      );
    }

    if (filteredItems.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 780) {
              return const SizedBox.shrink();
            }
            return _PdfListPanel(
              scrollController: _pdfScrollController,
              title: _selectedFolderPath == null
                  ? 'No folder selected'
                  : _displayFolderName(_selectedFolderPath!),
              items: visiblePdfs,
              onShare: widget.onShare,
              onOpen: widget.onOpen,
            );
          },
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }

  String _folderPathFor(MediaResource item) {
    final raw = (item.sourcePath?.trim().isNotEmpty == true)
        ? item.sourcePath!.trim()
        : item.title;
    final normalized = raw.replaceAll('\\', '/');
    if (!normalized.contains('/')) {
      return 'Root';
    }
    final segments = normalized.split('/').where((part) => part.trim().isNotEmpty).toList();
    if (segments.length <= 1) {
      return 'Root';
    }
    return segments.sublist(0, segments.length - 1).join('/');
  }

  String _displayFolderName(String folderPath) {
    if (folderPath == 'Root') {
      return 'Root';
    }
    final parts = folderPath.split('/');
    return parts.isEmpty ? folderPath : parts.last;
  }

  Future<void> _openFolderPicker(
    BuildContext context,
    List<_FolderEntry> folders,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            children: [
              const ListTile(
                title: Text(
                  'Folders',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView.builder(
                    itemCount: folders.length,
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      return ListTile(
                        leading: const Icon(Icons.folder_rounded),
                        title: Text(
                          _displayFolderName(folder.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(folder.path),
                        trailing: Text('${folder.items.length}'),
                        onTap: () => Navigator.of(context).pop(folder.path),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _selectedFolderPath = selected;
    });
  }
}

class _TaggedTextbook {
  const _TaggedTextbook({required this.item, required this.tag});

  final MediaResource item;
  final _TextbookTag tag;
}

class _FolderEntry {
  const _FolderEntry({required this.path, required this.items});

  final String path;
  final List<MediaResource> items;
}

class _PdfListPanel extends StatelessWidget {
  const _PdfListPanel({
    required this.scrollController,
    required this.title,
    required this.items,
    required this.onShare,
    required this.onOpen,
  });

  final ScrollController scrollController;
  final String title;
  final List<MediaResource> items;
  final Future<void> Function(MediaResource) onShare;
  final Future<void> Function(MediaResource) onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text('${items.length} PDFs', style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('No PDFs found in this folder.'))
                    : Scrollbar(
                        controller: scrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _TextbookCard(
                              title: item.title,
                              author: 'Offline Local Resource',
                              size: _formatSize(item.sizeBytes),
                              icon: Icons.book_rounded,
                              onShare: () => onShare(item),
                              onOpen: () => onOpen(item),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideosTab extends StatelessWidget {
  const _VideosTab({
    required this.items,
    required this.onShare,
  });

  final List<MediaResource> items;
  final Future<void> Function(MediaResource) onShare;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Text('No videos available. Use video import button in top bar.'),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader('Available Video Lectures'),
        ...items.map(
          (item) => _VideoCard(
            title: item.title,
            duration: '--:--',
            views: 'Local file',
            thumbnail: Icons.play_circle_outline_rounded,
            videoPath: item.localPath,
            subtitle: 'Size: ${_formatSize(item.sizeBytes)}',
            onShare: () => onShare(item),
          ),
        ),
      ],
    );
  }
}

class _ResourcesTab extends StatelessWidget {
  const _ResourcesTab({
    required this.items,
    required this.importing,
    required this.onImportFromP2P,
    required this.onOpen,
    required this.onShare,
  });

  final List<MediaResource> items;
  final bool importing;
  final VoidCallback onImportFromP2P;
  final Future<void> Function(MediaResource) onOpen;
  final Future<void> Function(MediaResource) onShare;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No shared resources yet. Import files from P2P inbox.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: importing ? null : onImportFromP2P,
                icon: importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: const Text('Import From P2P Inbox'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(child: _SectionHeader('Shared Study Materials')),
            FilledButton.icon(
              onPressed: importing ? null : onImportFromP2P,
              icon: importing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: const Text('Sync'),
            ),
          ],
        ),
        ...items.map(
          (item) => _ResourceCard(
            title: item.title,
            description: 'Size: ${_formatSize(item.sizeBytes)}',
            icon: _resourceIconFor(item.title),
            color: const Color(0xFF10B981),
            onTap: () => onOpen(item),
            onShare: () => onShare(item),
          ),
        ),
      ],
    );
  }
}

class _NotesTab extends StatelessWidget {
  const _NotesTab({
    required this.notes,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<StudyNote> notes;
  final VoidCallback onAdd;
  final Future<void> Function(StudyNote note) onEdit;
  final Future<void> Function(StudyNote note) onDelete;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No study notes yet. Add your first note.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.note_add_rounded),
                label: const Text('Add Note'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(child: _SectionHeader('My Study Notes')),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            ),
          ],
        ),
        ...notes.map(
          (note) => _NoteCard(
            title: note.title,
            preview: note.body,
            date: _formatNoteDate(note.updatedAt),
            tags: const <String>['Personal'],
            onTap: () => onEdit(note),
            onDelete: () => onDelete(note),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _TextbookCard extends StatelessWidget {
  const _TextbookCard({
    required this.title,
    required this.author,
    required this.size,
    required this.icon,
    required this.onShare,
    required this.onOpen,
  });

  final String title;
  final String author;
  final String size;
  final IconData icon;
  final VoidCallback onShare;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onOpen,
        leading: Container(
          width: 50,
          height: 70,
          decoration: BoxDecoration(
            color: const Color(0xFF0B6E4F).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, color: const Color(0xFF0B6E4F), size: 28),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(author, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(size, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        trailing: IconButton(
          tooltip: 'Share via P2P',
          onPressed: onShare,
          icon: const Icon(Icons.send_rounded),
        ),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.title,
    required this.duration,
    required this.views,
    required this.thumbnail,
    required this.videoPath,
    required this.onShare,
    this.subtitle,
  });

  final String title;
  final String duration;
  final String views;
  final IconData thumbnail;
  final String videoPath;
  final VoidCallback onShare;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(
                videoUrl: videoPath,
                title: title,
                subtitle: subtitle,
                description: subtitle,
              ),
            ),
          );
        },
        child: Row(
          children: [
            Container(
              width: 120,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  bottomLeft: Radius.circular(4),
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(thumbnail, size: 36, color: const Color(0xFF6366F1)),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        duration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      views,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Share via P2P',
              onPressed: onShare,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.onShare,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(description),
        trailing: IconButton(
          tooltip: 'Share via P2P',
          onPressed: onShare,
          icon: const Icon(Icons.send_rounded),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.title,
    required this.preview,
    required this.date,
    required this.tags,
    required this.onTap,
    required this.onDelete,
  });

  final String title;
  final String preview;
  final String date;
  final List<String> tags;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Row(
                    children: [
                      Text(date, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      IconButton(
                        onPressed: onDelete,
                        tooltip: 'Delete note',
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      ),
                    ],
                  ),
                  ],
              ),
              const SizedBox(height: 8),
              Text(
                preview,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: tags
                    .map(
                      (tag) => Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatSize(int sizeBytes) {
  if (sizeBytes <= 0) {
    return '0 B';
  }
  final kb = sizeBytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(1)} MB';
  }
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GB';
}

String _formatNoteDate(int epochMs) {
  if (epochMs <= 0) {
    return 'Unknown';
  }

  final date = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inDays == 0) {
    return 'Today';
  }
  if (diff.inDays == 1) {
    return 'Yesterday';
  }
  return '${date.day}/${date.month}/${date.year}';
}

IconData _resourceIconFor(String title) {
  final lower = title.toLowerCase();
  if (lower.endsWith('.pdf')) {
    return Icons.picture_as_pdf_rounded;
  }
  if (lower.endsWith('.mp4') ||
      lower.endsWith('.mkv') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.avi')) {
    return Icons.movie_rounded;
  }
  if (lower.endsWith('.json')) {
    return Icons.data_object_rounded;
  }
  if (lower.endsWith('.txt') || lower.endsWith('.md')) {
    return Icons.description_rounded;
  }
  return Icons.insert_drive_file_rounded;
}

class _TextbookTag {
  const _TextbookTag({
    required this.medium,
    required this.subject,
    required this.gradeLabel,
  });

  final String medium;
  final String subject;
  final String gradeLabel;
}

_TextbookTag _classifyTextbook(MediaResource item) {
  final basis = '${item.title} ${item.sourcePath ?? ''} ${item.localPath}'.toLowerCase();

  final medium = (basis.contains('kannada') || basis.contains(' kan '))
      ? 'Kannada Medium'
      : 'English Medium';

  String subject = 'Other Subject';
  if (basis.contains('math') || basis.contains('maths')) {
    subject = 'Mathematics';
  } else if (basis.contains('science') || basis.contains('sci')) {
    subject = 'Science';
  } else if (basis.contains('social') || basis.contains('history') || basis.contains('civics')) {
    subject = 'Social Science';
  } else if (basis.contains('english') || basis.contains('grammar') || basis.contains('prose')) {
    subject = 'English';
  }

  String gradeLabel = 'Unmapped Grade';
  final rangeMatch = RegExp(r'(12|11|10|[1-9])\s*-\s*(12|11|10|[1-9])').firstMatch(basis);
  if (rangeMatch != null) {
    gradeLabel = 'Grades ${rangeMatch.group(1)}-${rangeMatch.group(2)}';
  } else {
    final singleMatch = RegExp(r'(?<!\d)(12|11|10|[1-9])(?:st|nd|rd|th)?(?!\d)').firstMatch(basis);
    if (singleMatch != null) {
      gradeLabel = 'Grade ${singleMatch.group(1)}';
    }
  }

  return _TextbookTag(
    medium: medium,
    subject: subject,
    gradeLabel: gradeLabel,
  );
}

int _gradeSortValue(String label) {
  final firstNumber = RegExp(r'(12|11|10|[1-9])').firstMatch(label);
  if (firstNumber == null) {
    return 999;
  }
  return int.tryParse(firstNumber.group(1) ?? '999') ?? 999;
}
