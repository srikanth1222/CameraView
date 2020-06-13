import AVFoundation
import UIKit

protocol CameraControllerDelegate: NSObjectProtocol {
    
    func didCaptureImage(image: UIImage)
}

class CameraController: UIViewController {
    
    private var captureSession: AVCaptureSession?
    
    private var frontCamera: AVCaptureDevice?
    private var frontCameraInput: AVCaptureDeviceInput?
    
    private var photoOutput: AVCapturePhotoOutput?
    
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    private var photoCaptureCompletionBlock: ((UIImage?, Error?) -> Void)?
    
    private var capturePreviewView: UIView!
    private var captureButton: UIButton!
    
    weak var delegate: CameraControllerDelegate?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        capturePreviewView = UIView()
        capturePreviewView.backgroundColor = .black
        view.addSubview(capturePreviewView)
        capturePreviewView.translatesAutoresizingMaskIntoConstraints = false
        [
            capturePreviewView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0),
            capturePreviewView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 0),
            capturePreviewView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: 0),
            capturePreviewView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0),
            ].forEach { (constraint) in
                constraint.isActive = true }
        
        captureButton = UIButton(type: .custom)
        captureButton.addTarget(self, action: #selector(capturePicture), for: .touchUpInside)
        captureButton.backgroundColor = .white
        view.addSubview(captureButton)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        [
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: 10),
            captureButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.2, constant: 0),
            captureButton.heightAnchor.constraint(equalTo: captureButton.widthAnchor, multiplier: 1, constant: 0)
            ].forEach { (constraint) in
                constraint.isActive = true }
        
        DispatchQueue.main.asyncAfter(deadline: .now()+0.1) {
            self.styleCaptureButton()
        }
        configureCamera()
    }
    
    private func configureCamera() {
        self.prepare {(error) in
            if let error = error {
                print(error)
            }
            
            try? self.displayPreview(on: self.capturePreviewView)
        }
    }
    
    private func styleCaptureButton() {
        captureButton.layer.borderColor = UIColor.black.cgColor
        captureButton.layer.borderWidth = 2
        captureButton.layer.cornerRadius = min(captureButton.frame.width, captureButton.frame.height) / 2
    }
    
    @objc private func capturePicture() {
        
        self.captureImage {(image, error) in
            guard let image = image else {
                print(error ?? "Image capture error")
                return
            }
            
            self.delegate?.didCaptureImage(image: image)
        }
    }
}

extension CameraController {
    
    func prepare(completionHandler: @escaping (Error?) -> Void) {
        
        func createCaptureSession() {
            self.captureSession = AVCaptureSession()
        }
        
        func configureCaptureDevices() throws {
            
            let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .front)
            
            let cameras = session.devices.compactMap { $0 }
            guard !cameras.isEmpty else { throw CameraControllerError.noCamerasAvailable }
            
            for camera in cameras {
                if camera.position == .front {
                    self.frontCamera = camera
                }
            }
        }
        
        func configureDeviceInputs() throws {
            guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }
                
            if let frontCamera = self.frontCamera {
                self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
                
                if captureSession.canAddInput(self.frontCameraInput!) { captureSession.addInput(self.frontCameraInput!) }
                else { throw CameraControllerError.inputsAreInvalid }
            }
            
            else { throw CameraControllerError.noCamerasAvailable }
        }
        
        func configurePhotoOutput() throws {
            guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }
            
            self.photoOutput = AVCapturePhotoOutput()
            self.photoOutput!.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey : AVVideoCodecType.jpeg])], completionHandler: nil)
            
            if captureSession.canAddOutput(self.photoOutput!) { captureSession.addOutput(self.photoOutput!) }
            captureSession.startRunning()
        }
        
        DispatchQueue(label: "prepare").async {
            do {
                createCaptureSession()
                try configureCaptureDevices()
                try configureDeviceInputs()
                try configurePhotoOutput()
            }
                
            catch {
                DispatchQueue.main.async {
                    completionHandler(error)
                }
                
                return
            }
            
            DispatchQueue.main.async {
                completionHandler(nil)
            }
        }
    }
    
    func displayPreview(on view: UIView) throws {
        guard let captureSession = self.captureSession, captureSession.isRunning else { throw CameraControllerError.captureSessionIsMissing }
        
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        self.previewLayer?.connection?.videoOrientation = .portrait
        
        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = view.frame
    }
    
    func captureImage(completion: @escaping (UIImage?, Error?) -> Void) {
        guard let captureSession = captureSession, captureSession.isRunning else { completion(nil, CameraControllerError.captureSessionIsMissing); return }
        
        let settings = AVCapturePhotoSettings()
        self.photoOutput?.capturePhoto(with: settings, delegate: self)
        self.photoCaptureCompletionBlock = completion
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        if let imageData = photo.fileDataRepresentation(), let image = UIImage(data: imageData) {
            self.photoCaptureCompletionBlock?(image, nil)
        }
        else {
            self.photoCaptureCompletionBlock?(nil, CameraControllerError.unknown)
        }
    }
}

extension CameraController {
    
    enum CameraControllerError: Swift.Error {
        case captureSessionAlreadyRunning
        case captureSessionIsMissing
        case inputsAreInvalid
        case invalidOperation
        case noCamerasAvailable
        case unknown
    }
    
    public enum CameraPosition {
        case front
        case rear
    }
}
