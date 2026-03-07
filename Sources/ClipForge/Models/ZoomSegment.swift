import CoreGraphics
import Foundation

/// A timed zoom block: ramps in, holds at peak, ramps out.
struct ZoomSegment: Identifiable, Codable {
    let id: UUID
    var startTime: Double       // seconds from start of video
    var duration: Double        // total block length (easeIn + hold + easeOut)
    var scale: CGFloat          // peak zoom level (0.25 – 3.0)
    var center: CGPoint         // normalised focus point (0…1)
    var easeIn: Double          // seconds to ramp up
    var easeOut: Double         // seconds to ramp down
    var isEnabled: Bool

    var endTime: Double { startTime + duration }

    init(id: UUID = UUID(),
         startTime: Double,
         duration: Double = 2.0,
         scale: CGFloat = 2.0,
         center: CGPoint = CGPoint(x: 0.5, y: 0.5),
         easeIn: Double = 0.4,
         easeOut: Double = 0.4,
         isEnabled: Bool = true) {
        self.id = id
        self.startTime = startTime
        self.duration  = duration
        self.scale     = scale
        self.center    = center
        self.easeIn    = max(0, min(easeIn,  duration / 2))
        self.easeOut   = max(0, min(easeOut, duration / 2))
        self.isEnabled = isEnabled
    }

    /// Scale/center evaluated at a local time within the segment (0…duration).
    func interpolated(localT: Double) -> (scale: CGFloat, center: CGPoint) {
        func smooth(_ t: Double) -> Double { let t = max(0, min(1, t)); return t * t * (3 - 2 * t) }
        func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(smooth(t)) }

        let holdStart = easeIn
        let holdEnd   = duration - easeOut

        if localT <= holdStart && holdStart > 0 {
            let p = localT / holdStart
            return (lerp(1.0, scale, p),
                    CGPoint(x: lerp(0.5, center.x, p), y: lerp(0.5, center.y, p)))
        } else if localT >= holdEnd && easeOut > 0 {
            let p = (localT - holdEnd) / easeOut
            return (lerp(scale, 1.0, p),
                    CGPoint(x: lerp(center.x, 0.5, p), y: lerp(center.y, 0.5, p)))
        } else {
            return (scale, center)
        }
    }
}
