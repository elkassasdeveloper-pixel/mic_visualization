class TagImages {
  TagImages._();

  static const String _basePath = 'assets/images/tags';

  static const Map<String, String> _paths = {
    'Speech': '$_basePath/Speech.png',
    'Police car (siren)': '$_basePath/Police car (siren).png',
    'Ambulance (siren)': '$_basePath/Ambulance (siren).png',
    'Emergency vehicle': '$_basePath/Emergency vehicle.png',
    'Gunshot, gunfire': '$_basePath/Gunshot, gunfire.png',
    'Alarm': '$_basePath/Alarm.png',
    'Bark': '$_basePath/Bark.png',
    'Vehicle horn, car horn, honking': '$_basePath/Vehicle horn, car horn, honking.png',
    'Crying, sobbing': '$_basePath/Crying, sobbing.png',
    'Screaming': '$_basePath/Screaming.png',
    'dog': '$_basePath/dog.png',
    'cat': '$_basePath/cat.png',
    'cow': '$_basePath/cow.png',
    'frog': '$_basePath/frog.png',
  };

  static String? forLabel(String label) => _paths[label];
}