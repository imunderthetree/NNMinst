# NNMINST - Arabic Digit Recognition (MAHDBase)

[![GitHub stars](https://img.shields.io/github/stars/imunderthetree/NNMinst?style=social)](https://github.com/imunderthetree/NNMinst)
![Views](https://visitor-badge.laobi.icu/badge?page_id=imunderthetree.NNMinst)

NNMINST is an end-to-end project for Arabic handwritten digit recognition using
the MAHDBase dataset. It includes training code, exported models (Keras and
TFLite), and a Flutter app that detects and classifies multiple digits in a
single image or drawing.

Live demo: https://nnminst.netlify.app/

## Features

- On-device inference with a bundled TFLite model
- Camera, gallery, and drawing input
- Multi-digit detection by segmenting regions and classifying each crop
- Output sequence plus per-digit confidence breakdown
- Clean Flutter UI with Settings and About screens

## Model accuracy

Measured in `training/nnminst.ipynb` on the MAHDBase splits:

- Validation accuracy: 99.38%
- Test accuracy: 99.58%

## Tech stack

- Flutter + Dart (mobile app)
- TensorFlow + Keras (training)
- TensorFlow Lite (on-device inference)
- Python + NumPy + scikit-learn (training pipeline)
- MAHDBase dataset

## How it works

1. Detect ink regions in the input image or drawing using adaptive thresholding
	 and connected-components filtering.
2. Crop each detected region and normalize it to the model input size.
3. Run the TFLite classifier on each crop.
4. Sort boxes by reading order and display the predicted sequence.

## Repository layout

```
flutter_app/   Flutter mobile app (camera, gallery, draw input)
models/        Model exports (Keras + TFLite) and metadata
training/      Training notebook + helper script
```

## Quick start (Flutter app)

Requirements:

- Flutter 3.7+ (Dart 3.7)

Run:

```bash
cd flutter_app
flutter pub get
flutter run
```

Build a release APK:

```bash
cd flutter_app
flutter build apk
```

## Dataset (not included)

Download MAHDBase from the AUC dataset page and extract it into `data/`:

- MAHDBase training set: https://datacenter.aucegypt.edu/shazeem/Files/MAHDBase_TrainingSet.rar
- MAHDBase testing set: https://datacenter.aucegypt.edu/shazeem/Files/MAHDBase_TestingSet.rar
- Dataset homepage: https://datacenter.aucegypt.edu/shazeem/

Expected layout:

```
data/MAHDBase_TrainingSet/Part01/writer001_pass01_digit0.bmp
...
data/MAHDBase_TrainingSet/Part12/*.bmp
```

## Train and export

Install dependencies:

```bash
python -m pip install tensorflow pillow matplotlib numpy scikit-learn
```

Run the notebook:

```
training/nnminst.ipynb
```

Or run the helper script:

```bash
python training/train_notebook_model.py
```

Outputs are saved to `models/`:

```
models/model.keras
models/best_model.keras
models/model.tflite
models/model_meta.json
```

If you retrain, update the Flutter asset with:

```powershell
copy models\model.tflite flutter_app\assets\model.tflite
```

## Model contract

- Input shape: [1, 64, 64, 1]
- Input type: float32
- Normalization: grayscale / 255.0 (dark ink on white)
- Output shape: [1, 10]

## Notes

- The exported model is a single-digit classifier. Multi-digit output is
	produced by the app's detector and cropper.
- Touching digits may be detected as a single region; leave spacing for best
	results.

## License

No license has been specified yet.
