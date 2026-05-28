# NNMINST - Arabic Digit Recognition (MAHDBase)

NNMINST is an end-to-end project for Arabic handwritten digit recognition using
the MAHDBase dataset. It includes training code, exported models (Keras and
TFLite), and a Flutter mobile app that detects and classifies multiple digits in
a single image or drawing.

## Highlights

- On-device inference with a bundled TFLite model
- Camera, gallery, and drawing input
- Multi-digit detection by segmenting regions and classifying each crop
- Clean Flutter UI with Settings and About screens

## Repository layout

```
flutter_app/   Flutter mobile app (camera, gallery, draw input)
models/        Model exports (Keras + TFLite) and metadata
training/      Training notebook + helper script
```

## Quick start (Flutter app)

```bash
cd flutter_app
flutter pub get
flutter run
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
