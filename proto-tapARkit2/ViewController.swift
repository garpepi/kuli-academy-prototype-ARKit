//
//  ViewController.swift
//  proto-tapARkit2
//
//  Created by Garpepi Aotearoa on 01/08/21.
//

import UIKit
import SceneKit
import ARKit
import RealityKit

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
  // MARK: - IBOutlets

  @IBOutlet weak var sessionInfoView: UIView!
  @IBOutlet weak var sessionInfoLabel: UILabel!
  @IBOutlet weak var sceneView: ARSCNView!
  @IBOutlet weak var point: UIView!

  var dots = [SCNNode]()
  var line = SCNNode()
  var lines = [SCNNode]()
  var initialDotX:Float = 0.0
  var initialDotY:Float = 0.0

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view.
  }

  /// - Tag: StartARSession
  override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)

      // Start the view's AR session with a configuration that uses the rear camera,
      // device position and orientation tracking, and plane detection.
      let configuration = ARWorldTrackingConfiguration()
      configuration.planeDetection = [.horizontal, .vertical]
      sceneView.session.run(configuration)

      // Set a delegate to track the number of plane anchors for providing UI feedback.
      sceneView.session.delegate = self
      sceneView.isPlaying = true
      sceneView.delegate = self

      // Prevent the screen from being dimmed after a while as users will likely
      // have long periods of interaction without touching the screen or buttons.
      UIApplication.shared.isIdleTimerDisabled = true

      // Show debug UI to view performance metrics (e.g. frames per second).
      sceneView.showsStatistics = true
      point.layer.position.x = UIScreen.main.bounds.maxX / 2
      point.layer.position.y = UIScreen.main.bounds.maxY / 2

  }

  override func viewWillDisappear(_ animated: Bool) {
      super.viewWillDisappear(animated)

      // Pause the view's AR session.
      sceneView.session.pause()
  }

  // MARK: - ARSCNViewDelegate

  /// - Tag: PlaceARContent
  func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
      // Place content only for anchors found by plane detection.
      guard let planeAnchor = anchor as? ARPlaneAnchor else { return }

      // Create a custom object to visualize the plane geometry and extent.
      let plane = Plane(anchor: planeAnchor, in: sceneView)
      // Add the visualization to the ARKit-managed node so that it tracks
      // changes in the plane anchor as plane estimation continues.
      node.addChildNode(plane)
  }

  /// - Tag: UpdateARContent
  func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
      // Update only anchors and nodes set up by `renderer(_:didAdd:for:)`.
      guard let planeAnchor = anchor as? ARPlaneAnchor,
          let plane = node.childNodes.first as? Plane
          else { return }
      // Update ARSCNPlaneGeometry to the anchor's new estimated shape.
      if let planeGeometry = plane.meshNode.geometry as? ARSCNPlaneGeometry {
          planeGeometry.update(from: planeAnchor.geometry)
      }

      // Update extent visualization to the anchor's new bounding rectangle.
      if let extentGeometry = plane.extentNode.geometry as? SCNPlane {
          extentGeometry.width = CGFloat(planeAnchor.extent.x)
          extentGeometry.height = CGFloat(planeAnchor.extent.z)
          plane.extentNode.simdPosition = planeAnchor.center
      }

      // Update the plane's classification and the text position

      if #available(iOS 12.0, *),
          let classificationNode = plane.classificationNode,
          let classificationGeometry = classificationNode.geometry as? SCNText {
        let currentClassification = "\(planeAnchor.classification.description)"
          if let oldClassification = classificationGeometry.string as? String, oldClassification != currentClassification {
              classificationGeometry.string = currentClassification
              classificationNode.centerAlign()
          }
      }

  }

  // MARK: - ARSessionDelegate

  func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
      guard let frame = session.currentFrame else { return }
      updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
  }

  func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
      guard let frame = session.currentFrame else { return }
      updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
  }

  func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
      updateSessionInfoLabel(for: session.currentFrame!, trackingState: camera.trackingState)
  }

  // MARK: - ARSessionObserver

  func sessionWasInterrupted(_ session: ARSession) {
      // Inform the user that the session has been interrupted, for example, by presenting an overlay.
      sessionInfoLabel.text = "Session was interrupted"
  }

  func sessionInterruptionEnded(_ session: ARSession) {
      // Reset tracking and/or remove existing anchors if consistent tracking is required.
      sessionInfoLabel.text = "Session interruption ended"
      resetTracking()
  }

  func session(_ session: ARSession, didFailWithError error: Error) {
      sessionInfoLabel.text = "Session failed: \(error.localizedDescription)"
      guard error is ARError else { return }

      let errorWithInfo = error as NSError
      let messages = [
          errorWithInfo.localizedDescription,
          errorWithInfo.localizedFailureReason,
          errorWithInfo.localizedRecoverySuggestion
      ]

      // Remove optional error messages.
      let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")

      DispatchQueue.main.async {
          // Present an alert informing about the error that has occurred.
          let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
          let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
              alertController.dismiss(animated: true, completion: nil)
              self.resetTracking()
          }
          alertController.addAction(restartAction)
          self.present(alertController, animated: true, completion: nil)
      }
  }

  // MARK: - Private methods

  private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
      // Update the UI to provide feedback on the state of the AR experience.
      let message: String

      switch trackingState {
      case .normal where frame.anchors.isEmpty:
          // No planes detected; provide instructions for this app's AR interactions.
          message = "Move the device around to detect horizontal and vertical surfaces."

      case .notAvailable:
          message = "Tracking unavailable."

      case .limited(.excessiveMotion):
          message = "Tracking limited - Move the device more slowly."

      case .limited(.insufficientFeatures):
          message = "Tracking limited - Point the device at an area with visible surface detail, or improve lighting conditions."

      case .limited(.initializing):
          message = "Initializing AR session."

      default:
          // No feedback needed when tracking is normal and planes are visible.
          // (Nor when in unreachable limited-tracking states.)
          message = ""

      }

      sessionInfoLabel.text = message
      sessionInfoView.isHidden = message.isEmpty
  }

  private func resetTracking() {
      let configuration = ARWorldTrackingConfiguration()
      configuration.planeDetection = [.horizontal, .vertical]
      sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
  }

  @IBAction func buttonTap(_ sender: Any) {
    let x = UIScreen.main.bounds.maxX / 2
    let y = UIScreen.main.bounds.maxY / 2

//    let hitTestResultScene = sceneView.hitTest(CGPoint(x: x, y: y), types: .featurePoint)
//    if !hitTestResultScene.isEmpty {
//      guard let hitResultScene = hitTestResultScene.first else {
//          return
//      }
//      addDotScene(at: hitResultScene)
//            print("hitResultScene.worldTransform.columns.3 : \(hitResultScene.worldTransform.columns.3)")
//        }
//

    guard let raycastQuery = sceneView.raycastQuery(from: CGPoint(x: x, y: y), allowing: .existingPlaneGeometry, alignment: .any) else {
      return
    }
    let hitTestResult = sceneView.session.raycast(raycastQuery)
    if !hitTestResult.isEmpty {
            guard let hitResult = hitTestResult.first else {
                return
            }
      addDot(at: hitResult)
            print("hitResult.worldTransform.columns.3 : \(hitResult.worldTransform.columns.3)")
        }
  }
  @IBAction func reset(_ sender: Any) {
    line.removeFromParentNode()
    for dot in dots {
      dot.removeFromParentNode()
      dots.removeFirst()
    }
  }

//  func addDotScene(at location: ARHitTestResult) {
//    let dot = SCNSphere(radius: 0.007)
//    let material = SCNMaterial()
//    material.diffuse.contents = UIColor(red: 50.0 / 255.0, green: 150.0 / 255.0, blue: 30.0 / 255.0, alpha: 1)
//    let node = SCNNode(geometry: dot)
//
//    print("addDotScene : x: \(location.worldTransform.columns.3.x), y: \(location.worldTransform.columns.3.x), z: \(location.worldTransform.columns.3.z)")
//    node.position = SCNVector3(x: location.worldTransform.columns.3.x, y: location.worldTransform.columns.3.y, z: location.worldTransform.columns.3.z)
//    sceneView.scene.rootNode.addChildNode(node)
//    dots.append(node)
//
//    if(dots.count > 1){
//      //addLines(dots[dots.count-2], dots[dots.count-1])
//
//    }
//
//  }

  func addDot(at location: ARRaycastResult) {
    let dot = SCNSphere(radius: 0.007)
    let material = SCNMaterial()
    material.diffuse.contents = [material]
    let node = SCNNode(geometry: dot)

    print("addDot : x: \(location.worldTransform.columns.3.x), y: \(location.worldTransform.columns.3.x), z: \(location.worldTransform.columns.3.z)")
    node.position = SCNVector3(x: location.worldTransform.columns.3.x, y: location.worldTransform.columns.3.y, z: location.worldTransform.columns.3.z)
    sceneView.scene.rootNode.addChildNode(node)
    dots.append(node)

    if(dots.count == 1){
      initialDotX = location.worldTransform.columns.3.x - initialDotX
      initialDotY = location.worldTransform.columns.3.y - initialDotY
    }
    if(dots.count >= 2){
      addLines(dots[dots.count-2], dots[dots.count-1])
    }

  }

  func addLines(_ firstPoint: SCNNode, _ secondPoint: SCNNode) {
    let vertices: [SCNVector3] = [
               SCNVector3(firstPoint.position.x, firstPoint.position.y, firstPoint.position.z),
               SCNVector3(secondPoint.position.x, secondPoint.position.y, secondPoint.position.z)
           ]

     let linesGeometry = SCNGeometry(
         sources: [
             SCNGeometrySource(vertices: vertices)
         ],
         elements: [
             SCNGeometryElement(
                 indices: [Int32]([0, 1]),
                 primitiveType: .line
             )
         ]
     )

     line = SCNNode(geometry: linesGeometry)
     sceneView.scene.rootNode.addChildNode(line)

    let distance = sqrt(pow((secondPoint.position.x - firstPoint.position.x), 2) + pow((secondPoint.position.y - firstPoint.position.y), 2) + pow(0, 2))
    print("Listed FROM : (\(firstPoint.position.x),\(firstPoint.position.y)) TO: (\(secondPoint.position.x),\(secondPoint.position.y)) DISTANCE: \(distance)")

    let fromX = firstPoint.position.x - initialDotX
    let fromY = firstPoint.position.y - initialDotY
    let toX = secondPoint.position.x - initialDotY
    let toY = secondPoint.position.y - initialDotY
    print("ENCHANTED \(initialDotX),\(initialDotY) FROM : (\(fromX),\(fromY)) TO: (\(toX),\(toY)) DISTANCE: \(distance*100)")


  }

}

