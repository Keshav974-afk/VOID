import 'dart:io';

import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../core/services/vision/mirage_vision_model_manager.dart';
import '../../../core/services/vision/mirage_vision_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_text_button.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/snackbar.dart';

class ImageSettingsPage extends StatefulWidget {
  const ImageSettingsPage({super.key});

  @override
  State<ImageSettingsPage> createState() => _ImageSettingsPageState();
}

class _ImageSettingsPageState extends State<ImageSettingsPage> {
  final MirageVisionModelManager _mirageManager =
      MirageVisionModelManager.instance;
  bool _isInstalled = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadMirageStatus();
  }

  Future<void> _loadMirageStatus() async {
    final installed = await _mirageManager.isInstalled();
    if (mounted) {
      setState(() {
        _isInstalled = installed;
      });
    }
  }

  Future<void> _downloadModel() async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      await _mirageManager.downloadModel(
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _downloadProgress = p.progress ?? 0.0;
            });
          }
        },
      );
      if (mounted) {
        showAppSnackBar(
          context,
          message: 'Mirage 22M downloaded successfully',
          type: NotificationType.success,
        );
        context.read<SettingsProvider>().setMirageVisionEnabled(true);
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: 'Download failed: $e',
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
        });
        _loadMirageStatus();
      }
    }
  }

  void _cancelDownload() {
    _mirageManager.cancelDownload();
    if (mounted) {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
      });
      showAppSnackBar(
        context,
        message: 'Download cancelled',
        type: NotificationType.info,
      );
      _loadMirageStatus();
    }
  }

  Future<void> _deleteModel() async {
    try {
      await _mirageManager.deleteModel();
      if (mounted) {
        context.read<SettingsProvider>().setMirageVisionEnabled(false);
        showAppSnackBar(
          context,
          message: 'Mirage 22M deleted',
          type: NotificationType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: 'Delete failed: $e',
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        _loadMirageStatus();
      }
    }
  }

  Future<void> _testImageRecognition(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null ||
          result.files.isEmpty ||
          result.files.single.path == null) {
        return;
      }

      final file = File(result.files.single.path!);
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogCtx) => _MirageTestDialog(imageFile: file),
      );
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: 'Could not select image: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final compressionEnabled =
        settings.imageUploadQuality != ImageUploadQuality.original;

    final qualityRows = <Widget>[
      for (final quality in ImageUploadQuality.values)
        _QualityRow(
          title: _qualityTitle(quality, l10n),
          subtitle: _qualitySubtitle(quality, l10n),
          selected: settings.imageUploadQuality == quality,
          onTap: () =>
              context.read<SettingsProvider>().setImageUploadQuality(quality),
        ),
      if (settings.imageUploadQuality == ImageUploadQuality.custom)
        _CustomQualityRow(
          value: settings.imageCompressCustomQuality,
          onChanged: (value) => context
              .read<SettingsProvider>()
              .setImageCompressCustomQuality(value),
        ),
      _ToggleRow(
        title: l10n.imageSettingsPageCompressTransparentTitle,
        subtitle: l10n.imageSettingsPageCompressTransparentSubtitle,
        value: settings.imageCompressTransparentEnabled,
        onChanged: compressionEnabled
            ? (value) => context
                  .read<SettingsProvider>()
                  .setImageCompressTransparentEnabled(value)
            : null,
      ),
    ];

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.imageSettingsPageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SettingsSection(
            title: 'On-Device Vision (Mirage)',
            footer:
                'Mirage 22M by Cactus Compute is an ultra-compact ~22 MB vision model running entirely locally on your device for scene understanding, object detection, and OCR text extraction without sending images to the cloud.',
            children: [
              _ToggleRow(
                title: 'Prefer On-Device Vision (Mirage)',
                subtitle: _isInstalled
                    ? 'Route image OCR and visual understanding to local Mirage model'
                    : 'Download Mirage 22M below to enable on-device image recognition',
                value: settings.mirageVisionEnabled && _isInstalled,
                onChanged: _isInstalled
                    ? (value) => context
                          .read<SettingsProvider>()
                          .setMirageVisionEnabled(value)
                    : null,
              ),
              _buildMirageModelTile(
                model: _mirageManager.model,
                cs: cs,
                settings: settings,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsSection(
            title: l10n.imageSettingsPageEditSectionTitle,
            children: [
              _ToggleRow(
                title: l10n.displaySettingsPageEnableImageCropperTitle,
                subtitle: l10n.displaySettingsPageEnableImageCropperSubtitle,
                value: settings.imageCropperEnabled,
                onChanged: (value) => context
                    .read<SettingsProvider>()
                    .setImageCropperEnabled(value),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsSection(
            title: l10n.imageSettingsPageSendSectionTitle,
            children: [
              _ToggleRow(
                title: l10n.imageSettingsPageMarkdownImageLinksTitle,
                subtitle: l10n.imageSettingsPageMarkdownImageLinksSubtitle,
                value: settings.sendMarkdownImageLinksAsImages,
                onChanged: (value) => context
                    .read<SettingsProvider>()
                    .setSendMarkdownImageLinksAsImages(value),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsSection(
            title: l10n.imageSettingsPageQualitySectionTitle,
            footer: l10n.imageSettingsPageFooter,
            children: qualityRows,
          ),
        ],
      ),
    );
  }

  Widget _buildMirageModelTile({
    required MirageVisionModelDefinition model,
    required ColorScheme cs,
    required SettingsProvider settings,
  }) {
    final isSelected = settings.mirageVisionEnabled && _isInstalled;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _isInstalled
                      ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                      : _isDownloading
                      ? cs.primary.withValues(alpha: 0.15)
                      : cs.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _isInstalled
                      ? Lucide.Check
                      : _isDownloading
                      ? Lucide.Loader
                      : Lucide.Eye,
                  size: 18,
                  color: _isInstalled
                      ? const Color(0xFF22C55E)
                      : _isDownloading
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            model.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: AppFontWeights.emphasis,
                              color: cs.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Active',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: AppFontWeights.bold,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatBytes(model.downloadBytes)} · ${_isDownloading
                          ? "Downloading ${(_downloadProgress * 100).toInt()}%"
                          : _isInstalled
                          ? "Downloaded & Ready"
                          : "Not Downloaded"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isDownloading
                            ? cs.primary
                            : _isInstalled
                            ? const Color(0xFF22C55E)
                            : cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (model.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              model.description,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
          if (_isDownloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _downloadProgress > 0 ? _downloadProgress : null,
              backgroundColor: cs.onSurface.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!_isInstalled && !_isDownloading)
                IosTextButton(
                  label: 'Download (22 MB)',
                  icon: Lucide.Download,
                  fontSize: 12,
                  onPressed: _downloadModel,
                ),
              if (_isDownloading)
                IosTextButton(
                  label: 'Cancel',
                  icon: Lucide.X,
                  fontSize: 12,
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  onPressed: _cancelDownload,
                ),
              if (_isInstalled) ...[
                if (!isSelected)
                  IosTextButton(
                    label: 'Use for Vision & OCR',
                    icon: Lucide.Check,
                    fontSize: 12,
                    onPressed: () {
                      Haptics.light();
                      settings.setMirageVisionEnabled(true);
                    },
                  ),
                const SizedBox(width: 8),
                IosTextButton(
                  label: 'Test Image',
                  icon: Lucide.ScanEye,
                  fontSize: 12,
                  onPressed: () => _testImageRecognition(context),
                ),
                const SizedBox(width: 8),
                IosTextButton(
                  label: 'Delete',
                  icon: Lucide.Trash2,
                  fontSize: 12,
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  onPressed: _deleteModel,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MirageTestDialog extends StatefulWidget {
  const _MirageTestDialog({required this.imageFile});

  final File imageFile;

  @override
  State<_MirageTestDialog> createState() => _MirageTestDialogState();
}

class _MirageTestDialogState extends State<_MirageTestDialog> {
  bool _loading = true;
  String? _result;

  @override
  void initState() {
    super.initState();
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    try {
      final res = await MirageVisionService.instance.processImage(
        widget.imageFile,
      );
      if (mounted) {
        setState(() {
          _result = res ?? '*(No visual perception output returned)*';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = 'Error during Mirage analysis: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Lucide.ScanEye, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mirage 22M Image Recognition',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: AppFontWeights.emphasis,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Lucide.X,
                      size: 18,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 150,
                  width: double.infinity,
                  color: cs.onSurface.withValues(alpha: 0.05),
                  child: Image.file(widget.imageFile, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.2),
                      width: 0.8,
                    ),
                  ),
                  child: _loading
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 12),
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  cs.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Analyzing image on-device with Mirage 22M...',
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurface.withValues(alpha: 0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                          ],
                        )
                      : SingleChildScrollView(
                          child: SelectableText(
                            _result ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: cs.onSurface.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IosTextButton(
                    label: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
    this.footer,
  });

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) const _SettingsDivider(),
              ],
            ],
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              footer!,
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: cs.onSurface.withValues(alpha: 0.58),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosCardPress(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      baseColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        child: Row(
          children: [
            Expanded(
              child: _RowText(title: title, subtitle: subtitle),
            ),
            const SizedBox(width: 12),
            AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Icon(Lucide.Check, size: 18, color: cs.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomQualityRow extends StatelessWidget {
  const _CustomQualityRow({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 12, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.imageSettingsPageCustomQualityTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ),
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.68),
                ),
              ),
            ],
          ),
          SfSliderTheme(
            data: SfSliderThemeData(
              activeTrackHeight: 8,
              inactiveTrackHeight: 8,
              overlayRadius: 14,
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.onSurface.withValues(
                alpha: isDark ? 0.25 : 0.20,
              ),
              tooltipBackgroundColor: cs.primary,
              tooltipTextStyle: TextStyle(
                color: cs.onPrimary,
                fontWeight: AppFontWeights.semibold,
              ),
              thumbStrokeColor: Colors.transparent,
              thumbStrokeWidth: 0,
              activeTickColor: cs.onSurface.withValues(
                alpha: isDark ? 0.45 : 0.35,
              ),
              inactiveTickColor: cs.onSurface.withValues(
                alpha: isDark ? 0.30 : 0.25,
              ),
            ),
            child: SfSlider(
              value: value.toDouble(),
              min: 10.0,
              max: 100.0,
              stepSize: 5.0,
              interval: 10.0,
              showTicks: true,
              enableTooltip: true,
              shouldAlwaysShowTooltip: false,
              tooltipShape: const SfPaddleTooltipShape(),
              thumbIcon: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                  boxShadow: isDark
                      ? []
                      : [
                          BoxShadow(
                            color: cs.shadow.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
              ),
              onChanged: (next) => onChanged((next as double).round()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onChanged == null ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: _RowText(title: title, subtitle: subtitle),
            ),
            const SizedBox(width: 12),
            IosSwitch(value: value, semanticLabel: title, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _RowText extends StatelessWidget {
  const _RowText({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: AppFontWeights.semibold,
            color: cs.onSurface.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            height: 1.25,
            color: cs.onSurface.withValues(alpha: 0.62),
          ),
        ),
      ],
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 0.6,
      indent: 14,
      endIndent: 12,
      color: cs.outlineVariant.withValues(alpha: 0.18),
    );
  }
}

String _qualityTitle(ImageUploadQuality quality, AppLocalizations l10n) {
  return switch (quality) {
    ImageUploadQuality.original => l10n.imageSettingsPageQualityOriginal,
    ImageUploadQuality.high => l10n.imageSettingsPageQualityHigh,
    ImageUploadQuality.balanced => l10n.imageSettingsPageQualityBalanced,
    ImageUploadQuality.saver => l10n.imageSettingsPageQualitySaver,
    ImageUploadQuality.custom => l10n.imageSettingsPageQualityCustom,
  };
}

String _qualitySubtitle(ImageUploadQuality quality, AppLocalizations l10n) {
  return switch (quality) {
    ImageUploadQuality.original =>
      l10n.imageSettingsPageQualityOriginalSubtitle,
    ImageUploadQuality.high => l10n.imageSettingsPageQualityHighSubtitle,
    ImageUploadQuality.balanced =>
      l10n.imageSettingsPageQualityBalancedSubtitle,
    ImageUploadQuality.saver => l10n.imageSettingsPageQualitySaverSubtitle,
    ImageUploadQuality.custom => l10n.imageSettingsPageQualityCustomSubtitle,
  };
}
