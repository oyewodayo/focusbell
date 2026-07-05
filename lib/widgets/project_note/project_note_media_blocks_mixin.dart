// ─────────────────────────────────────────────────────────────────────────────
// project_note_media_blocks_mixin.dart
//
// UI builders for non-text (media) content blocks:
//   buildImageBlock()      — fullscreen-tappable image card
//   buildRecordingPanel()  — pulsing REC indicator that slides up while active
//   buildAudioBlock()      — waveform-style voice-note player
//   buildPdfBlock()        — PDF attachment card with Open + Remove
//
// All methods are public so project_note_text_blocks_mixin can call them via
// the block router (_buildBlock switch).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:focusbell/models/note_models.dart';
import 'package:focusbell/widgets/note_waveform_bars.dart';
import 'package:focusbell/widgets/project_note_sheet.dart';
import 'package:open_filex/open_filex.dart';

import 'project_note_state_interface.dart';
import 'project_note_actions_mixin.dart';

mixin ProjectNoteMediaBlocksMixin
    on State<ProjectNoteSheet>, NoteStateInterface, ProjectNoteActionsMixin {

  // ─────────────────────────────────────────────────────────────────────────
  // Image block
  // ─────────────────────────────────────────────────────────────────────────

  Widget buildImageBlock(NoteBlock b) {
    return GestureDetector(
      // Tap anywhere on the image to open the fullscreen viewer.
      onTap: () => setState(() => fullscreenImage = b.imagePath),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        constraints: const BoxConstraints(maxHeight: 280),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Image fills the container; falls back to a broken-image icon.
            Image.file(
              File(b.imagePath!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.white24, size: 40),
              ),
            ),

            // ✕ remove button — top-right corner.
            Positioned(
              top: 8, right: 8,
              child: GestureDetector(
                onTap: () => confirmRemoveBlock(b),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                ),
              ),
            ),

            // "View" label — bottom-left, signals tappability.
            Positioned(
              bottom: 8, left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.open_in_full_rounded, size: 11, color: Colors.white70),
                    SizedBox(width: 4),
                    Text('View',
                        style: TextStyle(color: Colors.white70,
                            fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Recording panel
  // ─────────────────────────────────────────────────────────────────────────

  /// Slides in at the bottom of the screen while a recording is in progress.
  /// Shows a pulsing red dot, elapsed time, Cancel, and Stop buttons.
  Widget buildRecordingPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF130A0A),
        border: Border(
            top: BorderSide(color: const Color(0xFFFF3B30).withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          // Pulsing red recording dot.
          AnimatedBuilder(
            animation: pulseAnim,
            builder: (_, __) => Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.fromRGBO(255, 59, 48, pulseAnim.value),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF3B30).withValues(alpha: pulseAnim.value * 0.6),
                    blurRadius: 8, spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // "REC" badge.
          const Text('REC',
              style: TextStyle(color: Color(0xFFFF3B30), fontSize: 11,
                  fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(width: 10),

          // Elapsed time counter (MM:SS).
          Text(
            _fmtDur(recElapsed),
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w300,
                fontFeatures: [FontFeature.tabularFigures()], letterSpacing: 1),
          ),

          const Spacer(),

          // Cancel — discards the in-progress recording.
          GestureDetector(
            onTap: cancelRecording,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(width: 10),

          // Stop — saves the recording as an audio block.
          GestureDetector(
            onTap: stopRecording,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30), borderRadius: BorderRadius.circular(20)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stop_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 5),
                  Text('Stop',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Audio block
  // ─────────────────────────────────────────────────────────────────────────

  /// Modern waveform-style voice-note player.
  /// Supports play/pause, seek scrubbing, duration display,
  /// drag-to-reorder, delete, and move-to-project.
  Widget buildAudioBlock(NoteBlock b) {
    final isPlaying = playing[b.id] ?? false;
    final pos = playPos[b.id] ?? Duration.zero;
    final dur = playDur[b.id] ?? b.audioDuration;
    final progress = dur.inMilliseconds > 0
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final remaining = dur > pos ? dur - pos : Duration.zero;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPlaying
              ? const Color(0xFF0A84FF).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.07),
        ),
        boxShadow: isPlaying
            ? [BoxShadow(
                color: const Color(0xFF0A84FF).withValues(alpha: 0.12),
                blurRadius: 20, offset: const Offset(0, 4))]
            : null,
      ),
      child: Column(
        children: [
          // ── Top row: play button, waveform, time, drag + delete ────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                // Play / Pause button.
                GestureDetector(
                  onTap: () => togglePlayback(b),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isPlaying
                          ? const Color(0xFF0A84FF)
                          : const Color(0xFF0A84FF).withValues(alpha: 0.15),
                      border: Border.all(
                        color: const Color(0xFF0A84FF).withValues(alpha: isPlaying ? 0.0 : 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: isPlaying ? Colors.white : const Color(0xFF0A84FF),
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Waveform visualiser + elapsed / remaining labels.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      WaveformBars(
                        progress: progress.toDouble(),
                        isPlaying: isPlaying,
                        onSeek: (f) => seekAudio(b, f),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(_fmtDur(pos),
                              style: TextStyle(
                                color: isPlaying ? const Color(0xFF0A84FF) : Colors.white38,
                                fontSize: 11, fontWeight: FontWeight.w600,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              )),
                          const Spacer(),
                          Text('-${_fmtDur(remaining)}',
                              style: const TextStyle(color: Colors.white24, fontSize: 11,
                                  fontFeatures: [FontFeature.tabularFigures()])),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),

                // Drag-to-reorder handle (index +1 because title is item 0).
                ReorderableDragStartListener(
                  index: blocks.indexWhere((bl) => bl.id == b.id) + 1,
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04), shape: BoxShape.circle),
                    child: const Icon(Icons.drag_handle_rounded, size: 14, color: Colors.white24),
                  ),
                ),
                const SizedBox(width: 6),

                // Delete button.
                GestureDetector(
                  onTap: () => confirmRemoveBlock(b),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white30),
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom strip: mic icon, label, total duration, Move button ──────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.mic_rounded, size: 12,
                    color: isPlaying
                        ? const Color(0xFF0A84FF).withValues(alpha: 0.7)
                        : Colors.white24),
                const SizedBox(width: 5),
                Text('Voice note',
                    style: TextStyle(
                        color: isPlaying
                            ? const Color(0xFF0A84FF).withValues(alpha: 0.7)
                            : Colors.white24,
                        fontSize: 11, fontWeight: FontWeight.w500)),
                const Spacer(),
                // Total duration.
                if (dur != Duration.zero) ...[
                  Text(_fmtDur(dur),
                      style: const TextStyle(color: Colors.white70, fontSize: 11,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(width: 8),
                ],

                // Share / save-to-device button — opens the native share sheet,
                // which includes "Save to Files" / download as one of its options.
                GestureDetector(
                  onTap: () => shareAudio(b),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.ios_share_rounded, size: 11, color: Colors.white54),
                        SizedBox(width: 4),
                        Text('Share',
                            style: TextStyle(color: Colors.white54,
                                fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Move-to-project / move-to-note button.
                GestureDetector(
                  onTap: () => showMoveSheet(b),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF64D2FF).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF64D2FF).withValues(alpha: 0.25)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.drive_file_move_outline, size: 11, color: Color(0xFF64D2FF)),
                        SizedBox(width: 4),
                        
                        Text('Move',
                            style: TextStyle(color: Color(0xFF64D2FF),
                                fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PDF block
  // ─────────────────────────────────────────────────────────────────────────

  Widget buildPdfBlock(NoteBlock b) {
    final name = b.pdfName ?? 'document.pdf';
    final sizeLabel = _fmtBytes(b.pdfSizeBytes);
    final pageLabel = b.pdfPageCount > 0
        ? '${b.pdfPageCount} page${b.pdfPageCount == 1 ? '' : 's'}'
        : 'PDF';

    return GestureDetector(
      onTap: () async { if (b.pdfPath != null) await OpenFilex.open(b.pdfPath!); },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF6B9D).withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            // PDF icon tile.
            Container(
              width: 42, height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF2E0A18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF6B9D).withValues(alpha: 0.4)),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFFF6B9D), size: 20),
                  SizedBox(height: 2),
                  Text('PDF',
                      style: TextStyle(color: Color(0xFFFF6B9D), fontSize: 8,
                          fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // File name + page count + size.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13,
                          fontWeight: FontWeight.w600, height: 1.3)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Text(pageLabel, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    const Text(' · ', style: TextStyle(color: Colors.white24, fontSize: 11)),
                    Text(sizeLabel, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Open button.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B9D).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFF6B9D).withValues(alpha: 0.3)),
              ),
              child: const Text('Open',
                  style: TextStyle(color: Color(0xFFFF6B9D),
                      fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),

            // Remove button.
            GestureDetector(
              onTap: () => confirmRemoveBlock(b),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, size: 14, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared formatting helpers used in this mixin ──────────────────────────

  /// Formats a [Duration] as "MM:SS".
  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Converts a byte count to a human-readable label (B / KB / MB).
  String _fmtBytes(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}