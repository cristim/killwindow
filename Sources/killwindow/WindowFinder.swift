import CoreGraphics
import Foundation

// Never target these — Window Server owns the cursor sprite (always under the
// click) and killing it signs the user out.
let protectedOwners: Set<String> = ["Window Server"]

func findWindow(at point: CGPoint, myPid: pid_t, anyLayer: Bool, debug: Bool) -> Target? {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
        if debug {
            FileHandle.standardError.write(Data("debug: CGWindowListCopyWindowInfo returned nil\n".utf8))
        }
        return nil
    }
    if debug {
        FileHandle.standardError.write(Data(
            "debug: click=(\(point.x), \(point.y)) windows=\(list.count) anyLayer=\(anyLayer)\n".utf8))
    }

    var result: Target?
    var layer0Count = 0
    var hitsByLayer: [Int: Int] = [:]

    // List is ordered front-to-back; first eligible hit wins.
    for win in list {
        let layer = (win[kCGWindowLayer as String] as? Int) ?? -999
        guard let boundsDict = win[kCGWindowBounds as String] as? [String: CGFloat],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        else { continue }
        if layer == 0 { layer0Count += 1 }

        let hit = bounds.contains(point)
        if hit { hitsByLayer[layer, default: 0] += 1 }

        let app = (win[kCGWindowOwnerName as String] as? String) ?? "?"
        let title = (win[kCGWindowName as String] as? String) ?? ""

        if debug && hit {
            FileHandle.standardError.write(Data(
                "  hit: layer=\(layer) bounds=(\(bounds.origin.x),\(bounds.origin.y) \(bounds.width)x\(bounds.height)) app=\(app) title=\"\(title)\"\n".utf8))
        }

        let pid = (win[kCGWindowOwnerPID as String] as? pid_t) ?? 0
        let layerOK = anyLayer ? true : (layer == 0)
        // Skip our own tooltip/highlight so we never target ourselves.
        if result == nil, hit, layerOK, pid != myPid, !protectedOwners.contains(app) {
            let wid = (win[kCGWindowNumber as String] as? CGWindowID) ?? 0
            result = Target(pid: pid, app: app, title: title, windowID: wid, bounds: bounds)
            if !debug { break }
        }
    }

    if debug {
        FileHandle.standardError.write(Data(
            "debug: layer0=\(layer0Count) hitsByLayer=\(hitsByLayer)\n".utf8))
    }
    return result
}
