# MAHDBase Digit Flutter App

This app bundles `assets/model.tflite` and runs on-device inference with a
two-stage pipeline:

1. Detect foreground digit regions in the camera/gallery image or drawing.
2. Crop each detected region and classify every crop with the TFLite model.

Each detected digit is drawn with a box in the preview, and the predicted
sequence is shown in the output box.

The TFLite classifier contract is:

- Input tensor: `[1, 64, 64, 1]`
- Input type: `float32`
- Normalization: black-digit-on-white grayscale `/ 255.0`
- Output tensor: `[1, 10]`

## Setup

Run:

```powershell
cd flutter_app
flutter pub get
flutter run
```

For iOS camera/gallery use, add `NSCameraUsageDescription` and
`NSPhotoLibraryUsageDescription` to `ios/Runner/Info.plist` after the platform
folder is generated.

If you regenerate or retrain the model, update the bundled asset:

```powershell
copy ..\models\model.tflite assets\model.tflite
```

The app has two inference paths:

- Draw: write one or more separated digits on the canvas and tap Predict.
- Image: classify one or more separated digits from camera or gallery.

The model is still a single-digit classifier. Multi-digit support is implemented
by the app's detector/cropper, so touching digits may need spacing to be split
into separate boxes.
