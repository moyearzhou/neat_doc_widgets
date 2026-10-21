# Custom PDF scroll thumbs

All `SfPdfViewer` constructors accept `scrollbarSettings` and
`scrollThumbBuilder`. Omitting them retains the built-in appearance and theme.

```dart
SfPdfViewer.memory(
  bytes,
  scrollbarSettings: const PdfScrollbarSettings(
    scrollHeadSize: Size(44, 32),
    scrollHeadTouchTargetSize: Size(48, 48),
    scrollHeadMargin: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    thickness: 6,
    minThumbLength: 50,
    thumbColor: Colors.grey,
    radius: Radius.circular(3),
    // autoHide: false, // null retains direction-dependent desktop behavior.
  ),
  scrollThumbBuilder: (context, details, defaultThumb) {
    if (!details.isScrollHead) return defaultThumb;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: details.isDragging ? Colors.blue : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: FittedBox(child: Text('${details.pageNumber}')),
      ),
    );
  },
)
```

- The mobile page handle uses `scrollHeadSize`, `scrollHeadTouchTargetSize`,
  `scrollHeadMargin` and optionally `scrollHeadDecoration`. Its existing colors
  and text styles can still be set through `SfPdfViewerTheme`.
- Desktop viewport bars use `thickness`, `minThumbLength`, `thumbColor`, `radius`,
  `padding`, `showHorizontalScrollbar`, `showVerticalScrollbar`, `autoHide` and
  `fadeOutDelay`. A null padding preserves the layout's existing reserved space.
- Single-page desktop mode also has a page navigation handle. Its size uses
  `thickness` and `minThumbLength` (defaults: 10 and 54), while viewport bars
  default to 8 and 50. `scrollHeadMargin` applies to this page handle.
- `details` supplies the axis, allocated visual size, current/total pages, hover
  and drag states. `isScrollHead` distinguishes page navigation from viewport
  scrolling. Viewport thumb length remains proportional to the zoomed content,
  subject to the configured minimum and available track length.
- The builder replaces visual content only. The SDK constrains its size, owns
  gestures and page-handle semantics, and ignores pointers inside custom
  content. Use the settings to change dimensions; do not add drag/tap handlers
  inside the builder or maintain a separate scroll offset.
- Continuous and single-page layouts share page-handle geometry. Margins and
  touch targets are included in the drag travel; tiny viewports clamp the thumb
  and disable dragging if no travel remains.
- Existing `canShowScrollHead`, `canShowScrollStatus` and
  `canShowPaginationDialog` keep their original scope. Desktop viewport bars
  have the separate visibility options above.

Run `flutter test test/pdf_scrollbar_test.dart` from this package to check
custom sizes, margins, zoomed drag bounds, auto-hide/hover, controller replacement
and continuous/single-page horizontal/vertical page navigation.
