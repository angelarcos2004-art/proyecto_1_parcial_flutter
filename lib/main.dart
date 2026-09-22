import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Punto de entrada de la aplicación Flutter.
void main() => runApp(const MyApp());

// Configuración global del tema y pantalla inicial.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Galería',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xff101314),
      useMaterial3: true,
    ),
    home: const GalleryPage(),
  );
}

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

// Controla la galería, favoritos, navegación y apertura del editor.
class _GalleryPageState extends State<GalleryPage> {
  static const _galleryColor = Color(0xff111315);
  final PageController _pageController = PageController();
  final List<AssetEntity> _assets = [];
  final Set<String> _favoriteIds = {};
  int _currentIndex = 0;
  int _selectedTab = 0;
  bool _isEditorOpen = false;
  bool _isLoading = true;
  String? _errorMessage;

  AssetEntity? get _currentAsset => _assets.isEmpty
      ? null
      : _assets[_currentIndex.clamp(0, _assets.length - 1)];

  @override
  void initState() {
    super.initState();
    _loadGallery();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadGallery() async {
    // Solicita acceso y carga imágenes de todos los álbumes disponibles.
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Se necesita permiso para acceder a tus fotos.';
        });
        return;
      }

      final preferences = await SharedPreferences.getInstance();
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: false,
      );
      final photoLists = await Future.wait(
        albums.map((album) => album.getAssetListPaged(page: 0, size: 200)),
      );

      final photos = <AssetEntity>[];
      for (final photoList in photoLists) {
        for (final photo in photoList) {
          if (!photos.any((item) => item.id == photo.id)) {
            photos.add(photo);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _assets
          ..clear()
          ..addAll(photos);
        _favoriteIds
          ..clear()
          ..addAll(preferences.getStringList('favorite_ids')?.toSet() ?? const <String>{});
        _currentIndex = 0;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'No se pudieron cargar las fotos.';
      });
    }
  }

  Future<void> _toggleFavorite() async {
    // Actualiza el favorito actual y persiste sus IDs localmente.
    final asset = _currentAsset;
    if (asset == null) return;
    final preferences = await SharedPreferences.getInstance();
    setState(() {
      if (_favoriteIds.contains(asset.id)) {
        _favoriteIds.remove(asset.id);
      } else {
        _favoriteIds.add(asset.id);
      }
    });
    await preferences.setStringList('favorite_ids', _favoriteIds.toList());
  }

  Future<void> _deleteCurrentAsset() async {
    // Elimina la fotografía del dispositivo después de confirmación.
    final asset = _currentAsset;
    if (asset == null) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar foto'),
        content: const Text('Esta acción eliminará la foto del dispositivo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      await PhotoManager.editor.deleteWithIds([asset.id]);
      if (!mounted) return;
      setState(() {
        _assets.removeAt(_currentIndex);
        _favoriteIds.remove(asset.id);
        if (_assets.isEmpty) {
          _currentIndex = 0;
        } else if (_currentIndex >= _assets.length) {
          _currentIndex = _assets.length - 1;
        }
      });
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList('favorite_ids', _favoriteIds.toList());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo eliminar la foto.')),
      );
    }
  }

  void _openEditor() {
    // Cambia el árbol principal de la galería al editor de la foto actual.
    if (_currentAsset == null) return;
    setState(() {
      _isEditorOpen = true;
    });
  }

  void _goToPhoto(int offset) {
    // Mueve el carrusel una posición hacia adelante o hacia atrás.
    if (_assets.isEmpty) return;
    final nextIndex = (_currentIndex + offset).clamp(0, _assets.length - 1);
    _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditorOpen && _currentAsset != null) {
      return PhotoEditorView(
        asset: _currentAsset!,
        onClose: () => setState(() => _isEditorOpen = false),
        onSaved: (savedAsset) {
          if (savedAsset == null || !mounted) return;
          final currentId = _currentAsset?.id;
          setState(() {
            if (currentId != null) {
              final index = _assets.indexWhere((a) => a.id == currentId);
              if (index >= 0) {
                _assets[index] = savedAsset;
              } else {
                _assets.insert(0, savedAsset);
                _currentIndex = 0;
              }
            }
            _isEditorOpen = false;
          });
        },
      );
    }

    return Scaffold(
      backgroundColor: _galleryColor,
      appBar: AppBar(
        backgroundColor: _galleryColor,
        title: const Text('Galería'),
        actions: [
          IconButton(
            onPressed: _loadGallery,
            tooltip: 'Actualizar galería',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          NavigationBar(
            height: 72,
            backgroundColor: _galleryColor,
            selectedIndex: _selectedTab,
            onDestinationSelected: (index) => setState(() => _selectedTab = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.photo_library_outlined),
                selectedIcon: Icon(Icons.photo_library),
                label: 'Todas',
              ),
              NavigationDestination(
                icon: Icon(Icons.favorite_border),
                selectedIcon: Icon(Icons.favorite),
                label: 'Favoritos',
              ),
            ],
          ),
          Expanded(
            child: ColoredBox(
              color: _galleryColor,
              child: _selectedTab == 0 ? _buildGalleryBody() : _buildFavoritesBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryBody() {
    // Construye el visor principal y las acciones inferiores.
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_library_outlined, size: 56),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadGallery,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_assets.isEmpty) {
      return const Center(child: Text('No hay fotos en el dispositivo.'));
    }

    final isFavorite = _currentAsset != null && _favoriteIds.contains(_currentAsset!.id);

    return SafeArea(
      child: ColoredBox(
        color: _galleryColor,
        child: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _assets.length,
                      onPageChanged: (index) => setState(() => _currentIndex = index),
                      itemBuilder: (context, index) => _AssetImage(asset: _assets[index]),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xff80DEEA),
                    child: const Icon(Icons.chevron_left, color: Colors.black),
                  ),
                ),
                Positioned(
                  right: 12,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xff80DEEA),
                    child: const Icon(Icons.chevron_right, color: Colors.black),
                  ),
                ),
                Positioned(
                  left: 8,
                  child: IconButton(
                    onPressed: _currentIndex > 0 ? () => _goToPhoto(-1) : null,
                    icon: const Icon(Icons.chevron_left, size: 28),
                  ),
                ),
                Positioned(
                  right: 8,
                  child: IconButton(
                    onPressed: _currentIndex < _assets.length - 1 ? () => _goToPhoto(1) : null,
                    icon: const Icon(Icons.chevron_right, size: 28),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _BottomAction(
                  icon: Icons.edit,
                  label: 'Editar',
                  onPressed: _openEditor,
                ),
                _BottomAction(
                  icon: isFavorite ? Icons.favorite : Icons.favorite_border,
                  label: 'Favoritos',
                  color: isFavorite ? Colors.red : null,
                  onPressed: _toggleFavorite,
                ),
                _BottomAction(
                  icon: Icons.delete_outline,
                  label: 'Eliminar',
                  color: Colors.red,
                  onPressed: _deleteCurrentAsset,
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildFavoritesBody() {
    // Construye la cuadrícula con las fotografías marcadas como favoritas.
    final favorites = _assets.where((asset) => _favoriteIds.contains(asset.id)).toList();
    if (favorites.isEmpty) {
      return const Center(child: Text('Aún no hay favoritos.'));
    }

    return ColoredBox(
      color: _galleryColor,
      child: GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final asset = favorites[index];
        return GestureDetector(
          onTap: () {
            final assetIndex = _assets.indexOf(asset);
            setState(() {
              _selectedTab = 0;
              _currentIndex = assetIndex;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _pageController.jumpToPage(assetIndex);
            });
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _AssetImage(asset: asset),
          ),
        );
      },
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color ?? Colors.white, size: 28),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}

enum PhotoEditorTool { draw, erase, crop }

// Representa un trazo completo para conservar color, grosor y modo goma.
class DrawOp {
  DrawOp({
    required this.path,
    required this.color,
    required this.strokeWidth,
    required this.isEraser,
  });

  final Path path;
  final Color color;
  final double strokeWidth;
  final bool isEraser;
}

class PhotoEditorView extends StatefulWidget {
  const PhotoEditorView({
    super.key,
    required this.asset,
    required this.onClose,
    required this.onSaved,
  });

  final AssetEntity asset;
  final VoidCallback onClose;
  final ValueChanged<AssetEntity?> onSaved;

  @override
  State<PhotoEditorView> createState() => _PhotoEditorViewState();
}

// Estado del editor: dibujo, goma, recorte y preparación de la imagen final.
class _PhotoEditorViewState extends State<PhotoEditorView>
  with SingleTickerProviderStateMixin {
  final List<DrawOp> _drawOps = [];
  final List<Color> _palette = const [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.white,
    Colors.black,
  ];

  PhotoEditorTool _tool = PhotoEditorTool.draw;
  Color _brushColor = Colors.red;
  double _brushSize = 8;
  bool _eraserMode = false;
  DrawOp? _activeOp;
  Rect _cropRect = Rect.zero;
  Size _canvasSize = Size.zero;
  Size _imageSize = Size.zero;
  Rect _imageBounds = Rect.zero;
  ui.Image? _editorImage;
  bool _isSaving = false;
  bool _cropInitialized = false;
  _CropHandleType? _activeCropHandle;
  Offset? _cropOrigin;

  @override
  void initState() {
    super.initState();
    _loadEditorImageSize();
  }

  Future<void> _loadEditorImageSize() async {
    // Carga una previsualización para mantener fluida la edición.
    final bytes = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize(1600, 1600),
    );
    if (bytes == null || !mounted) return;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      _editorImage = image;
      _cropInitialized = false;
    });
  }

  @override
  void dispose() {
    _editorImage?.dispose();
    super.dispose();
  }

  Rect _fitImageBounds(Size size) {
    // Calcula el rectángulo visible de la foto usando BoxFit.contain.
    if (_imageSize.isEmpty || size.isEmpty) return Offset.zero & size;
    final fitted = applyBoxFit(BoxFit.contain, _imageSize, size);
    return Alignment.center.inscribe(fitted.destination, Offset.zero & size);
  }

  Rect _clampCrop(Rect rect, Rect bounds) {
    // Mantiene el marco dentro de los límites reales de la imagen.
    final width = rect.width.clamp(80.0, bounds.width).toDouble();
    final height = rect.height.clamp(80.0, bounds.height).toDouble();
    final left = rect.left.clamp(bounds.left, bounds.right - width).toDouble();
    final top = rect.top.clamp(bounds.top, bounds.bottom - height).toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  void _initCropRectIfNeeded(Size size) {
    // Inicializa el marco una sola vez cuando ya se conocen las dimensiones.
    if (_cropInitialized || _imageSize.isEmpty || size.width == 0 || size.height == 0) {
      return;
    }
    _imageBounds = _fitImageBounds(size);
    if (_imageBounds.isEmpty) return;
    final width = size.width * 0.78;
    final height = size.height * 0.70;
    _cropRect = _clampCrop(
      Rect.fromCenter(
        center: _imageBounds.center,
        width: width,
        height: height,
      ),
      _imageBounds,
    );
    _cropInitialized = true;
  }

  void _beginDraw(Offset point) {
    // Inicia un trazo nuevo o una pasada de goma.
    final path = Path()..moveTo(point.dx, point.dy);
    setState(() {
      _activeOp = DrawOp(
        path: path,
        color: _eraserMode || _tool == PhotoEditorTool.erase
            ? Colors.transparent
            : _brushColor,
        strokeWidth: _brushSize,
        isEraser: _eraserMode || _tool == PhotoEditorTool.erase,
      );
    });
  }

  void _updateDraw(Offset point) {
    // Añade puntos al trazo mientras el usuario arrastra el dedo.
    if (_activeOp == null) return;
    final path = _activeOp!.path;
    setState(() {
      path.lineTo(point.dx, point.dy);
    });
  }

  void _endDraw() {
    // Guarda el trazo terminado para mostrarlo y exportarlo.
    if (_activeOp == null) return;
    setState(() {
      _drawOps.add(_activeOp!);
      _activeOp = null;
    });
  }

  void _undo() {
    // Deshace el último trazo o restablece el marco de recorte.
    if (_tool == PhotoEditorTool.draw) {
      setState(() {
        if (_activeOp != null) {
          _activeOp = null;
          return;
        }
        if (_drawOps.isNotEmpty) {
          _drawOps.removeLast();
        }
      });
      return;
    }

    setState(() {
      _cropRect = _imageBounds;
    });
  }

  void _restoreNormalViewport() {
    if (_imageBounds.isEmpty) return;
  }

  void _enterCropMode() {
    // Activa el modo de recorte con la imagen en su vista normal.
    _restoreNormalViewport();
    setState(() => _tool = PhotoEditorTool.crop);
  }

  void _beginCropGesture(Offset point) {
    // Detecta si el gesto inicia en una esquina o dentro del marco.
    _cropRect = _cropRect.intersect(_imageBounds);
    final handles = [
      _cropRect.topLeft,
      _cropRect.topRight,
      _cropRect.bottomLeft,
      _cropRect.bottomRight,
    ];

    for (final handle in handles) {
      if ((handle - point).distance < 24) {
        _activeCropHandle = _handleTypeFor(handle, _cropRect);
        return;
      }
    }

    if (_cropRect.contains(point)) {
      _cropOrigin = point;
    }
  }

  void _updateCrop(Offset point) {
    // Mueve el marco o cambia su tamaño respetando imageBounds.
    if (_cropOrigin != null) {
      final dx = point.dx - _cropOrigin!.dx;
      final dy = point.dy - _cropOrigin!.dy;
      _cropOrigin = point;
      final maxLeft = (_imageBounds.right - _cropRect.width)
          .clamp(_imageBounds.left, _imageBounds.right);
      final maxTop = (_imageBounds.bottom - _cropRect.height)
          .clamp(_imageBounds.top, _imageBounds.bottom);
        final nextLeft = (_cropRect.left + dx)
          .clamp(_imageBounds.left, maxLeft)
          .toDouble();
        final nextTop = (_cropRect.top + dy)
          .clamp(_imageBounds.top, maxTop)
          .toDouble();
      setState(() {
        _cropRect = _clampCrop(
          Rect.fromLTWH(nextLeft, nextTop, _cropRect.width, _cropRect.height),
          _imageBounds,
        );
      });
      return;
    }

    if (_activeCropHandle == null) return;

    final minSize = 80.0;
    final current = _cropRect;

    switch (_activeCropHandle!) {
      case _CropHandleType.topLeft:
        setState(() {
          final left = point.dx.clamp(_imageBounds.left, current.right - minSize).toDouble();
          final top = point.dy.clamp(_imageBounds.top, current.bottom - minSize).toDouble();
          _cropRect = _clampCrop(
            Rect.fromLTRB(left, top, current.right, current.bottom),
            _imageBounds,
          );
        });
      case _CropHandleType.topRight:
        setState(() {
          final left = current.left;
          final top = point.dy.clamp(_imageBounds.top, current.bottom - minSize).toDouble();
          final right = point.dx.clamp(current.left + minSize, _imageBounds.right).toDouble();
          final bottom = current.bottom;
          _cropRect = Rect.fromLTRB(left, top, right, bottom);
        });
      case _CropHandleType.bottomLeft:
        setState(() {
          final left = point.dx.clamp(_imageBounds.left, current.right - minSize).toDouble();
          final top = current.top;
          final right = current.right;
          final bottom = point.dy.clamp(current.top + minSize, _imageBounds.bottom).toDouble();
          _cropRect = Rect.fromLTRB(left, top, right, bottom);
        });
      case _CropHandleType.bottomRight:
        setState(() {
          final left = current.left;
          final top = current.top;
          final right = point.dx.clamp(current.left + minSize, _imageBounds.right).toDouble();
          final bottom = point.dy.clamp(current.top + minSize, _imageBounds.bottom).toDouble();
          _cropRect = Rect.fromLTRB(left, top, right, bottom);
        });
    }
  }

  void _endCropGesture() {
    // Finaliza el gesto de recorte y libera sus referencias activas.
    _cropOrigin = null;
    _activeCropHandle = null;
  }

  Future<void> _saveEditedImage() async {
    // Renderiza la imagen recortada, aplica los trazos y la guarda en la galería.
    final originalBytes = await widget.asset.originBytes ??
        await widget.asset.thumbnailDataWithSize(const ThumbnailSize(2000, 2000));
    if (originalBytes == null) {
      throw StateError('No se pudo leer la imagen original.');
    }

    final codec = await ui.instantiateImageCodec(originalBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final hasValidBounds = _imageBounds.width > 0 &&
      _imageBounds.height > 0 &&
      _cropRect.width > 0 &&
      _cropRect.height > 0;
    final sourceRect = hasValidBounds
      ? Rect.fromLTRB(
        ((_cropRect.left - _imageBounds.left) / _imageBounds.width * image.width)
          .clamp(0.0, image.width.toDouble())
          .toDouble(),
        ((_cropRect.top - _imageBounds.top) / _imageBounds.height * image.height)
          .clamp(0.0, image.height.toDouble())
          .toDouble(),
        ((_cropRect.right - _imageBounds.left) / _imageBounds.width * image.width)
          .clamp(0.0, image.width.toDouble())
          .toDouble(),
        ((_cropRect.bottom - _imageBounds.top) / _imageBounds.height * image.height)
          .clamp(0.0, image.height.toDouble())
          .toDouble(),
        )
      : Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final safeSourceRect = Rect.fromLTRB(
      sourceRect.left,
      sourceRect.top,
      sourceRect.right > sourceRect.left
        ? sourceRect.right
        : (sourceRect.left + 1).clamp(0.0, image.width.toDouble()).toDouble(),
      sourceRect.bottom > sourceRect.top
        ? sourceRect.bottom
        : (sourceRect.top + 1).clamp(0.0, image.height.toDouble()).toDouble(),
    );

    final outputWidth = safeSourceRect.width.round().clamp(1, image.width);
    final outputHeight = safeSourceRect.height.round().clamp(1, image.height);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final dst = Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble());
    canvas.drawImageRect(image, safeSourceRect, dst, Paint());

    final drawingRecorder = ui.PictureRecorder();
    final drawingCanvas = Canvas(drawingRecorder);
    drawingCanvas.saveLayer(
      Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
      Paint(),
    );
    for (final op in _drawOps) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = op.strokeWidth
        ..color = op.isEraser ? Colors.transparent : op.color
        ..blendMode = op.isEraser ? BlendMode.clear : BlendMode.srcOver;
      drawingCanvas.save();
      drawingCanvas.translate(-_cropRect.left, -_cropRect.top);
      drawingCanvas.scale(
        outputWidth / _cropRect.width,
        outputHeight / _cropRect.height,
      );
      drawingCanvas.drawPath(op.path, paint);
      drawingCanvas.restore();
    }
    drawingCanvas.restore();

    final drawingImage = await drawingRecorder.endRecording().toImage(
      outputWidth,
      outputHeight,
    );
    canvas.drawImage(drawingImage, Offset.zero, Paint());

    final result = await recorder.endRecording().toImage(outputWidth, outputHeight);
    final pngData = await result.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    drawingImage.dispose();
    result.dispose();

    if (pngData == null) {
      throw StateError('No se pudo generar la imagen final.');
    }

    final savedAsset = await PhotoManager.editor.saveImage(
      pngData.buffer.asUint8List(),
      filename: 'galeria_editada_${DateTime.now().millisecondsSinceEpoch}.png',
      title: 'Foto editada',
      relativePath: 'Pictures/Galeria',
    );

    if (!mounted) return;
    widget.onSaved(savedAsset);
  }

  Future<void> _handleSave() async {
    // Evita guardados duplicados y muestra el error real si la exportación falla.
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await _saveEditedImage();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $error')),
      );
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Editar foto'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                _ToolChip(
                  label: 'Dibujar',
                  selected: _tool == PhotoEditorTool.draw,
                  onTap: () {
                    _restoreNormalViewport();
                    setState(() {
                      _tool = PhotoEditorTool.draw;
                      _eraserMode = false;
                    });
                  },
                ),
                const SizedBox(width: 12),
                _ToolChip(
                  label: 'Recortar',
                  selected: _tool == PhotoEditorTool.crop,
                  onTap: _enterCropMode,
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _undo,
            tooltip: 'Deshacer',
            icon: const Icon(Icons.undo),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                _initCropRectIfNeeded(_canvasSize);

                return GestureDetector(
                  onPanStart: (details) {
                    final point = details.localPosition;
                    if (_tool != PhotoEditorTool.crop) {
                      _beginDraw(point);
                    } else {
                      _beginCropGesture(point);
                    }
                  },
                  onPanUpdate: (details) {
                    final point = details.localPosition;
                    if (_tool != PhotoEditorTool.crop) {
                      _updateDraw(point);
                    } else {
                      _updateCrop(point);
                    }
                  },
                  onPanEnd: (_) {
                    if (_tool != PhotoEditorTool.crop) {
                      _endDraw();
                    } else {
                      _endCropGesture();
                    }
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        child: RawImage(
                          image: _editorImage,
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.low,
                        ),
                      ),
                      CustomPaint(
                        painter: _StrokePainter(
                          drawOps: _drawOps,
                          activeOp: _activeOp,
                        ),
                      ),
                      if (_tool == PhotoEditorTool.crop)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _CropPainter(cropRect: _cropRect),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Column(
              children: [
                if (_tool != PhotoEditorTool.crop)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                    child: Row(
                      children: [
                        if (_tool == PhotoEditorTool.draw)
                          for (final color in _palette)
                            GestureDetector(
                            onTap: () => setState(() {
                              _brushColor = color;
                              _eraserMode = false;
                            }),
                            child: Container(
                              width: 26,
                              height: 26,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _brushColor == color ? Colors.white : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            ),
                        const Spacer(),
                        IconButton.filledTonal(
                          onPressed: () => setState(() {
                            _tool = PhotoEditorTool.draw;
                            _eraserMode = !_eraserMode;
                          }),
                          style: IconButton.styleFrom(
                            backgroundColor: _eraserMode
                                ? const Color(0xff80cbc4)
                                : const Color(0xff263238),
                            foregroundColor: _eraserMode
                                ? Colors.black
                                : Colors.white,
                          ),
                          icon: Icon(
                            Icons.cleaning_services_outlined,
                            color: _eraserMode ? Colors.black : Colors.white,
                          ),
                          tooltip: 'Goma',
                        ),
                      ],
                    ),
                  ),
                if (_tool != PhotoEditorTool.crop)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Text('Trazo'),
                        Expanded(
                          child: Slider(
                            value: _brushSize,
                            min: 2,
                            max: 30,
                            onChanged: (value) => setState(() => _brushSize = value),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: _isSaving ? null : widget.onClose,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xff80cbc4),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _isSaving ? null : _handleSave,
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text('Guardar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _CropHandleType _handleTypeFor(Offset point, Rect rect) {
    final center = rect.center;
    if (point.dx <= center.dx && point.dy <= center.dy) return _CropHandleType.topLeft;
    if (point.dx > center.dx && point.dy <= center.dy) return _CropHandleType.topRight;
    if (point.dx <= center.dx && point.dy > center.dy) return _CropHandleType.bottomLeft;
    return _CropHandleType.bottomRight;
  }
}

enum _CropHandleType { topLeft, topRight, bottomLeft, bottomRight }

class _StrokePainter extends CustomPainter {
  const _StrokePainter({required this.drawOps, required this.activeOp});

  final List<DrawOp> drawOps;
  final DrawOp? activeOp;

  @override
  void paint(Canvas canvas, Size size) {
    // Dibuja únicamente los trazos para no redibujar la fotografía completa.
    if (drawOps.isEmpty && activeOp == null) return;
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final op in [...drawOps, ...?activeOp == null ? null : [activeOp!]]) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = op.strokeWidth
        ..color = op.isEraser ? Colors.transparent : op.color
        ..blendMode = op.isEraser ? BlendMode.clear : BlendMode.srcOver;
      final path = Path()..addPath(op.path, Offset.zero);
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) =>
      oldDelegate.drawOps != drawOps ||
      oldDelegate.activeOp != activeOp;
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.label,
    required this.onTap,
    required this.selected,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xff80cbc4)
              : const Color(0xff263238),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  const _CropPainter({required this.cropRect});

  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    // Oscurece el exterior y dibuja borde, cuadrícula 3x3 y esquinas.
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(cropRect),
    );
    canvas.drawPath(path, Paint()..color = Colors.black54);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = 2;
    canvas.drawRect(cropRect, border);

    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;

    final stepX = cropRect.width / 3;
    final stepY = cropRect.height / 3;
    for (var i = 1; i < 3; i++) {
      final x = cropRect.left + stepX * i;
      final y = cropRect.top + stepY * i;
      canvas.drawLine(Offset(x, cropRect.top), Offset(x, cropRect.bottom), guide);
      canvas.drawLine(Offset(cropRect.left, y), Offset(cropRect.right, y), guide);
    }

    final handlePaint = Paint()..color = Colors.white;
    final handles = [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
    ];
    for (final handle in handles) {
      canvas.drawCircle(handle, 8, handlePaint);
      canvas.drawCircle(handle, 5.5, Paint()..color = Colors.black);
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) => oldDelegate.cropRect != cropRect;
}

class _AssetImage extends StatelessWidget {
  const _AssetImage({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: asset.thumbnailDataWithSize(const ThumbnailSize(1600, 1600)),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return Image.memory(snapshot.data!, fit: BoxFit.contain);
    },
  );
}
