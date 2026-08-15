import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacyShield: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    guard privacyShield == nil, let window else { return }

    let shield = UIView(frame: window.bounds)
    shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    shield.backgroundColor = UIColor(red: 0.075, green: 0.137, blue: 0.106, alpha: 1)

    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "KrishiSathi"
    label.textColor = .white
    label.font = .systemFont(ofSize: 24, weight: .semibold)
    shield.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: shield.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: shield.centerYAnchor),
    ])

    window.addSubview(shield)
    privacyShield = shield
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyShield?.removeFromSuperview()
    privacyShield = nil
  }

}
