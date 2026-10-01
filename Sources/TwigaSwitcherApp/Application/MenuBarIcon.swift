import AppKit

/// A template mark drawn at menu-bar size, rather than shrinking the app artwork.
/// The keyboard and giraffe stay intact in every state; only the upper-right badge changes.
enum MenuBarIcon {
    static func image(for state: AppState) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            NSGraphicsContext.saveGraphicsState()
            let giraffePosition = NSAffineTransform()
            giraffePosition.translateX(by: 0.6, yBy: 1)
            giraffePosition.concat()
            drawGiraffe()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            let keyboardPosition = NSAffineTransform()
            // Match the app artwork: the keyboard is about two thirds of
            // the giraffe's height, with a slightly taller frame aspect ratio.
            keyboardPosition.translateX(by: 6.2, yBy: 0.7)
            keyboardPosition.scaleX(by: 0.65, yBy: 0.72)
            keyboardPosition.concat()
            drawKeyboard()
            NSGraphicsContext.restoreGraphicsState()

            drawBadge(for: state)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Twiga Switcher — \(state.title)"
        return image
    }

    private static func drawGiraffe() {
        // Full-body silhouette: a sloping back, long angled neck, muzzle,
        // four separated legs and a tufted tail distinguish it at 18 points.
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 2.1, y: 6.2))
        body.curve(to: NSPoint(x: 2.8, y: 9), controlPoint1: NSPoint(x: 1.4, y: 7.2), controlPoint2: NSPoint(x: 1.8, y: 8.4))
        body.line(to: NSPoint(x: 5.8, y: 10))
        body.line(to: NSPoint(x: 8.9, y: 15.5))
        body.line(to: NSPoint(x: 10.6, y: 15.5))
        body.line(to: NSPoint(x: 12.9, y: 13.7))
        body.curve(to: NSPoint(x: 12.5, y: 12.8), controlPoint1: NSPoint(x: 13.4, y: 13.2), controlPoint2: NSPoint(x: 13, y: 12.7))
        body.line(to: NSPoint(x: 10.1, y: 13.4))
        body.line(to: NSPoint(x: 8.1, y: 8.4))
        body.curve(to: NSPoint(x: 6.8, y: 5.9), controlPoint1: NSPoint(x: 8.9, y: 7.1), controlPoint2: NSPoint(x: 8, y: 6))
        body.curve(to: NSPoint(x: 2.1, y: 6.2), controlPoint1: NSPoint(x: 5.1, y: 5.4), controlPoint2: NSPoint(x: 3.3, y: 5.6))
        body.close()
        body.fill()

        for (start, end) in [
            (NSPoint(x: 2.5, y: 6.8), NSPoint(x: 1.8, y: 0.9)),
            (NSPoint(x: 3.8, y: 6.2), NSPoint(x: 4.6, y: 0.9)),
            (NSPoint(x: 6.6, y: 6.6), NSPoint(x: 6.2, y: 0.9)),
            (NSPoint(x: 7.8, y: 6.9), NSPoint(x: 8.8, y: 0.9))
        ] {
            stroke(from: start, to: end, width: 1.15)
        }
        stroke(from: NSPoint(x: 2, y: 8), to: NSPoint(x: 0.7, y: 5.1), width: 0.65)
        NSBezierPath(ovalIn: NSRect(x: 0.1, y: 4.4, width: 1, height: 1.6)).fill()

        for x in [9.2, 10.5] {
            stroke(from: NSPoint(x: x, y: 15.2), to: NSPoint(x: x - 0.2, y: 17.1), width: 0.65)
            NSBezierPath(ovalIn: NSRect(x: x - 0.7, y: 16.7, width: 1, height: 1)).fill()
        }
        let ear = NSBezierPath()
        ear.move(to: NSPoint(x: 9.2, y: 15.1))
        ear.curve(to: NSPoint(x: 7.3, y: 16.2), controlPoint1: NSPoint(x: 8.1, y: 16.4), controlPoint2: NSPoint(x: 7.7, y: 16.3))
        ear.curve(to: NSPoint(x: 9.2, y: 15.1), controlPoint1: NSPoint(x: 7.5, y: 15), controlPoint2: NSPoint(x: 8.1, y: 14.8))
        ear.fill()

        // Negative-space eye and sparse patches work on light and dark bars.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: 10.4, y: 14.1, width: 0.75, height: 0.75)).fill()
        for (x, y) in [(8.2, 12.5), (7.2, 10.4), (5.9, 8.3), (3.2, 7.2)] {
            let patch = NSBezierPath()
            patch.move(to: NSPoint(x: x, y: y))
            patch.line(to: NSPoint(x: x + 0.8, y: y + 0.25))
            patch.line(to: NSPoint(x: x + 1, y: y - 0.55))
            patch.line(to: NSPoint(x: x + 0.25, y: y - 0.85))
            patch.close()
            patch.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawKeyboard() {
        // Clear the overlapping legs before drawing the foreground keyboard.
        // The transparent separation also works when macOS tints the template.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(roundedRect: NSRect(x: 0.1, y: 0.2, width: 19.6, height: 9), xRadius: 2, yRadius: 2).fill()
        NSGraphicsContext.restoreGraphicsState()
        let frame = NSBezierPath(roundedRect: NSRect(x: 0.8, y: 0.9, width: 18.2, height: 7.6), xRadius: 1.5, yRadius: 1.5)
        frame.lineWidth = 1.2
        frame.stroke()
        for column in 0..<5 {
            for y in [4.3, 6.3] {
                NSBezierPath(roundedRect: NSRect(x: 2.5 + Double(column) * 3.1, y: y, width: 2.2, height: 1.1), xRadius: 0.25, yRadius: 0.25).fill()
            }
        }
        NSBezierPath(roundedRect: NSRect(x: 4, y: 2.3, width: 12.2, height: 1.1), xRadius: 0.3, yRadius: 0.3).fill()
    }

    private static func drawBadge(for state: AppState) {
        guard state != .active else { return }

        NSGraphicsContext.saveGraphicsState()
        let badgePosition = NSAffineTransform()
        badgePosition.translateX(by: 2, yBy: 2)
        badgePosition.concat()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let outline: NSBezierPath
        if state == .permissionsRequired {
            outline = NSBezierPath()
            outline.move(to: NSPoint(x: 15.2, y: 19.2))
            outline.line(to: NSPoint(x: 19.2, y: 11.7))
            outline.line(to: NSPoint(x: 11.2, y: 11.7))
            outline.close()
            outline.lineJoinStyle = .round
        } else {
            outline = NSBezierPath(ovalIn: NSRect(x: 11, y: 11, width: 8.4, height: 8.4))
        }

        // A transparent halo separates the outlined badge from the artwork
        // without depending on the menu bar's background or template tint.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        outline.fill()
        outline.lineWidth = 2
        outline.stroke()
        NSGraphicsContext.restoreGraphicsState()
        outline.lineWidth = 0.9
        outline.stroke()

        switch state {
        case .active:
            break
        case .paused:
            for x in [12.9, 15.7] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 12.7, width: 1.8, height: 5), xRadius: 0.4, yRadius: 0.4).fill()
            }
        case .permissionsRequired:
            stroke(from: NSPoint(x: 15.2, y: 16.6), to: NSPoint(x: 15.2, y: 14.4), width: 1.2)
            NSBezierPath(ovalIn: NSRect(x: 14.6, y: 12.6, width: 1.2, height: 1.2)).fill()
        case .error:
            stroke(from: NSPoint(x: 13.4, y: 13.4), to: NSPoint(x: 17, y: 17), width: 1.3)
            stroke(from: NSPoint(x: 13.4, y: 17), to: NSPoint(x: 17, y: 13.4), width: 1.3)
        }
    }

    private static func stroke(from start: NSPoint, to end: NSPoint, width: CGFloat) {
        let line = NSBezierPath()
        line.lineWidth = width
        line.lineCapStyle = .round
        line.move(to: start)
        line.line(to: end)
        line.stroke()
    }
}
