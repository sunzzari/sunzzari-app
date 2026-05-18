import UIKit
import MapKit
import CoreLocation

/// Custom user-location annotation view showing a translucent heading cone + blue dot,
/// matching the Apple/Google Maps live-location style.
final class UserLocationAnnotationView: MKAnnotationView {

    static let reuseID = "userLocation"

    private static let size: CGFloat = 80
    private static let dotRadius: CGFloat = 9
    private static let coneLength: CGFloat = 36

    private let coneLayer = CAShapeLayer()
    private let dotRing   = CALayer()
    private let dotCore   = CALayer()

    // Tracks the last built half-angle to avoid redundant path rebuilds
    private var currentHalfAngle: CGFloat = 27.5 * .pi / 180

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let s = Self.size
        frame = CGRect(x: 0, y: 0, width: s, height: s)
        centerOffset = .zero
        isUserInteractionEnabled = false
        buildLayers()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildLayers() {
        let cx = bounds.midX
        let cy = bounds.midY
        let r  = Self.dotRadius

        // Cone — hidden until first valid heading arrives.
        // frame must match the view's bounds so anchorPoint (0.5, 0.5) resolves
        // to (cx, cy), keeping rotation centered on the blue dot.
        coneLayer.frame       = bounds
        coneLayer.fillColor   = UIColor.systemBlue.withAlphaComponent(0.22).cgColor
        coneLayer.strokeColor = UIColor.clear.cgColor
        coneLayer.path        = coneUpPath(from: CGPoint(x: cx, y: cy), halfAngle: currentHalfAngle)
        coneLayer.isHidden    = true
        layer.addSublayer(coneLayer)

        // White ring (shadow + border behind the dot)
        dotRing.backgroundColor = UIColor.white.cgColor
        dotRing.cornerRadius    = r + 2
        dotRing.frame = CGRect(x: cx - r - 2, y: cy - r - 2,
                               width: (r + 2) * 2, height: (r + 2) * 2)
        dotRing.shadowColor   = UIColor.black.cgColor
        dotRing.shadowOpacity = 0.28
        dotRing.shadowRadius  = 4
        dotRing.shadowOffset  = CGSize(width: 0, height: 1)
        layer.addSublayer(dotRing)

        // Blue core
        dotCore.backgroundColor = UIColor.systemBlue.cgColor
        dotCore.cornerRadius    = r
        dotCore.frame = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        layer.addSublayer(dotCore)
    }

    /// Wedge path pointing "up" (north) from center. setHeading rotates it.
    private func coneUpPath(from center: CGPoint, halfAngle: CGFloat) -> CGPath {
        let length = Self.coneLength
        let path = UIBezierPath()
        path.move(to: center)
        path.addArc(
            withCenter: center,
            radius: length,
            startAngle: -.pi / 2 - halfAngle,
            endAngle:   -.pi / 2 + halfAngle,
            clockwise: true
        )
        path.close()
        return path.cgPath
    }

    /// degrees: bearing relative to map (already corrected for map rotation).
    /// accuracy: CLHeading.headingAccuracy -- cone half-angle mirrors heading uncertainty,
    /// matching Google Maps' behavior where a wide cone = poor accuracy.
    func setHeading(_ degrees: CLLocationDirection, accuracy: CLLocationDirection = 27.5) {
        coneLayer.isHidden = false

        // Cone width: half-angle = accuracy, clamped to [5°, 65°].
        // Floor at 5° so cone stays visible at perfect accuracy.
        // Cap at 65° (130° total) to preserve the directional flashlight shape.
        let halfAngle = CGFloat(min(max(accuracy, 5), 65)) * .pi / 180
        if abs(halfAngle - currentHalfAngle) > 0.01 {
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            coneLayer.path = coneUpPath(from: center, halfAngle: halfAngle)
            CATransaction.commit()
            currentHalfAngle = halfAngle
        }

        // Rotate along the shortest arc
        let target = CGFloat(degrees) * .pi / 180
        let current = (coneLayer.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat) ?? 0
        var delta = target - current
        while delta > .pi  { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }

        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = current
        anim.toValue   = current + delta
        anim.duration  = 0.15
        coneLayer.add(anim, forKey: "headingRotation")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        coneLayer.setValue(current + delta, forKeyPath: "transform.rotation.z")
        CATransaction.commit()
    }
}
