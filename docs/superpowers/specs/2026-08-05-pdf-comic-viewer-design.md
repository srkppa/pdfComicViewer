# PDF Comic Viewer Design

## Summary

Build a personal macOS application for reading local comic PDFs. The application displays ordinary portrait pages as right-bound spreads, displays the cover and merged landscape spreads as single pages, and lets the reader correct page pairing or display mode without editing the PDF.

The first release is a practical minimum product for one user's Mac. It does not upload, copy, or modify opened PDFs and does not make network requests.

## Goals

- Open a PDF from a file picker or Finder drag and drop.
- Read right-bound comics as two-page spreads, with left-bound reading available per document.
- Display page 1 as a centered cover by default.
- Shift spread pairing by one physical PDF page when a document's page alignment differs.
- Switch quickly between single-page and spread display.
- Detect merged landscape spreads and show them alone while otherwise remaining in spread mode.
- Allow the reader to correct landscape detection for individual pages.
- Support fit-to-window, zoom, pan, keyboard navigation, click navigation, and full screen.
- Restore reading position and document-specific settings.
- Remain responsive with long or high-resolution PDFs.

## Non-goals for the first release

- Windows or Linux support.
- A library bookshelf, cover search, reading-status management, or metadata editing.
- Cloud storage, synchronization, accounts, or network access.
- PDF editing, annotation, conversion, or export.
- Mac App Store distribution, automatic updates, signing, or notarization.
- Animated page-turn effects.

## Technology

Use Swift, SwiftUI, AppKit integration, and PDFKit.

PDFKit provides document parsing, page access, rendering, navigation, and zoom support. SwiftUI provides the application shell, toolbar, state-driven controls, dialogs, and settings. AppKit bridges file and window behavior where SwiftUI or PDFKit needs native integration.

This native stack is preferred because the first release targets only macOS and values a small dependency surface, native file handling, and efficient PDF rendering over cross-platform reuse.

## Architecture

### `ReaderView`

The SwiftUI root for the reading window. It renders the toolbar, empty state, loading state, page area, page counter, password prompt, and recoverable errors. It forwards user intent to `ReaderViewModel` rather than manipulating PDFKit directly.

### `PDFSpreadView`

An `NSViewRepresentable` bridge around the PDFKit/AppKit rendering surface. It accepts one `DisplayUnit` at a time and lays out either one page or two pages against a dark background. It owns fit-to-window calculation, zoom, pan, and render-view reuse, but it does not decide which pages belong together.

### `ReaderViewModel`

The window-level state owner. It coordinates document loading, current display-unit selection, reading direction, display mode, pairing alignment, zoom commands, full-screen commands, and progress persistence.

### `DocumentSession`

Owns one opened `PDFDocument`, its file reference, page metadata, password-unlock state, and current `DocumentPreferences`. It exposes page count and page geometry without exposing persistence details to the UI.

### `SpreadBuilder`

A pure component that converts physical PDF page indexes into an ordered array of `DisplayUnit` values. It has no PDFKit view dependency and is table-tested independently.

```swift
enum DisplayUnit: Equatable {
    case single(pageIndex: Int)
    case pair(earlierPageIndex: Int, laterPageIndex: Int)
}
```

`earlierPageIndex` and `laterPageIndex` describe reading order. Visual left/right placement is applied later from the binding direction.

### `ReadingProgressStore`

Persists document preferences and a macOS bookmark reference in Application Support. Persistence is asynchronous and coalesced so rapid page turns do not synchronously write once per key press.

## Page grouping rules

PDF page indexes are zero-based internally and shown as one-based page numbers in the UI.

### Global single-page mode

Every physical PDF page becomes one `.single` display unit. A landscape page remains one physical page and is fitted as a wide image. Page navigation advances one PDF page at a time.

### Spread mode

Spread mode follows these rules in order:

1. Determine which pages must be displayed alone.
2. Page 1 is alone when cover alignment is enabled.
3. A page whose crop-box width is greater than its height is alone by automatic landscape detection.
4. A per-page manual override may force an automatically detected page to be pairable or force any page to be alone.
5. Remaining consecutive pages are paired in PDF order.
6. A forced-single page ends the current run. Pairing starts fresh with the next page.
7. If one page remains at the end of a run or document, it is displayed alone.

Automatic detection therefore produces this sequence for a document with a cover and a merged spread at physical page 4:

```text
[1]
[2, 3]
[4 landscape]
[5, 6]
```

### Pairing alignment

Each document has two alignment states:

- Cover alignment: `[1] [2,3] [4,5] ...`
- Shifted alignment: `[1,2] [3,4] [5,6] ...`

The “Shift spread by one page” command toggles these states. In spread mode, automatic or manually forced single pages remain boundaries; pages after each boundary are paired afresh. The alignment choice is persisted per document.

### Binding direction

Binding direction changes visual placement and navigation direction, not grouping:

- Right-bound pair `[2,3]`: page 2 on the right, page 3 on the left.
- Left-bound pair `[2,3]`: page 2 on the left, page 3 on the right.

Right-bound is the default. Binding direction is persisted per document.

## Reader interface

The initial empty state contains a prominent “Open PDF” action and accepts PDF drag and drop.

The reading window uses a black or dark-gray background. The toolbar contains:

- Open PDF
- Binding direction control
- Single-page / Spread segmented control
- Shift spread by one page
- Zoom out
- Fit to window
- Zoom in
- Full screen

The page counter appears as `12–13 / 180` for a pair and `12 / 180` for a single page. Controls automatically hide in full screen after inactivity and return on pointer movement.

The normal zoom state fits the entire current display unit in the available window without cropping. Zoomed content can be panned with dragging or trackpad scrolling. Changing pages returns to fit-to-window by default; transient zoom and pan are not persisted.

## Input behavior

Right-bound defaults:

| Input | Action |
| --- | --- |
| Left arrow or Space | Next display unit |
| Right arrow or Shift-Space | Previous display unit |
| Click left half | Next display unit |
| Click right half | Previous display unit |
| `1` | Single-page mode |
| `2` | Spread mode |
| `S` | Shift spread pairing by one page |
| Command-O | Open PDF |
| Command-Plus | Zoom in |
| Command-Minus | Zoom out |
| Command-0 | Fit to window |
| Command-Control-F | Toggle full screen |

Left-bound mode reverses the arrow and click-half meanings. Space and Shift-Space retain next/previous semantics in both directions.

A page context menu provides “Use automatic layout,” “Show this PDF page alone,” and “Allow this PDF page in a pair.” These commands are relevant in spread mode and update the per-page override immediately.

## Data flow

1. The user selects or drops a PDF URL.
2. `DocumentSession` validates and opens the `PDFDocument`.
3. If locked, the session asks `ReaderViewModel` to present a password prompt and retries unlock in memory.
4. `ReadingProgressStore` resolves saved preferences for the document bookmark.
5. `DocumentSession` reads page crop-box dimensions.
6. `SpreadBuilder` creates display units from page metadata and preferences.
7. The saved physical page index is mapped to the display unit containing it.
8. `PDFSpreadView` renders that unit with the selected binding direction.
9. Navigation changes the current unit and schedules a coalesced progress save.
10. Layout-setting changes rebuild display units while retaining the current physical page when possible.

## Persistence model

Persist the following per document:

- macOS bookmark data for the file URL
- last known normalized path for diagnostics and fallback matching
- file size and modification date to detect likely replacement
- last visible physical page index
- binding direction
- global display mode
- pairing alignment
- per-page layout overrides

If bookmark resolution fails, the application shows the last known filename and asks the user to locate the PDF again. Selecting a replacement updates the bookmark and retains preferences after user confirmation when size or modification metadata differs.

Passwords are never persisted.

## Rendering and performance

Keep rendered content for the current display unit and at most one unit before and after it. Cancel obsolete pre-render work after rapid navigation. Release distant page images and views so cache size does not scale with total page count.

PDF parsing and page-metadata collection must not block the main thread. UI state changes and PDFKit view updates occur on the main actor. Opening a large PDF shows a progress indicator until the first display unit is ready; remaining page metadata may be collected incrementally if full scanning is measurably slow.

## Error handling

- Unsupported or corrupt input: show a concise error and keep the open action available.
- Empty PDF: report that the document has no readable pages.
- Password-protected PDF: prompt for a password, report an incorrect password inline, and allow cancellation.
- Missing saved file: offer a locate-file action without deleting saved preferences automatically.
- Page render failure: show an error placeholder for that page while keeping navigation operational.
- Persistence failure: continue reading, show a non-blocking warning, and retry on the next state change or application close.

Opening a new document must not discard the currently readable document until validation of the new document succeeds.

## Testing

### Unit tests

Table-test `SpreadBuilder` with:

- odd and even page counts
- one-page and empty inputs
- cover and shifted alignment
- a landscape page at the beginning, middle, and end
- consecutive landscape pages
- manual force-single and force-pairable overrides
- leftover portrait pages adjacent to single-page boundaries
- switching display mode while preserving the physical-page anchor

Separately test the presentation mapper that converts each pair's reading order into right-bound and left-bound visual placement.

Test persistence encoding, decoding, bookmark replacement metadata, and corrupt saved data using isolated temporary storage.

### Integration tests

Use small local fixtures for portrait-only, mixed portrait/landscape, encrypted, empty, and intentionally corrupt PDFs. Verify open, password unlock, state restoration, drag and drop, menu commands, and keyboard navigation.

### UI and manual verification

- Resize the window through narrow, wide, and full-screen states.
- Confirm fit-to-window never crops a page at default zoom.
- Verify click regions and arrows in both binding directions.
- Verify a merged landscape spread is readable without changing global spread mode.
- Open a several-hundred-page high-resolution comic and navigate rapidly while observing responsiveness and bounded memory use.

## Acceptance criteria

The first release is complete when a user can open a local comic PDF, read it from beginning to end in right-bound spreads, correct a one-page pairing offset, view merged landscape spreads alone, override incorrect automatic decisions, switch between single and spread modes, navigate and zoom comfortably in full screen, quit, reopen the same PDF, and resume at the saved position without the PDF leaving the Mac or being modified.
