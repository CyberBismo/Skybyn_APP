enum SubProfileType { kid, pet, vehicle }

abstract class SubProfile {
  final String id;
  final String? avatar;
  final List<String> gallery;
  final SubProfileType type;

  SubProfile({
    required this.id,
    this.avatar,
    this.gallery = const [],
    required this.type,
  });

  factory SubProfile.fromJson(Map<String, dynamic> json) {
    String typeStr = json['type'] ?? '';
    if (typeStr == 'kid') return Kid.fromJson(json);
    if (typeStr == 'pet') return Pet.fromJson(json);
    if (typeStr == 'vehicle') return Vehicle.fromJson(json);
    throw Exception('Unknown subprofile type: $typeStr');
  }

  Map<String, dynamic> toJson();
}

class Kid extends SubProfile {
  final String name;
  final String? birth;
  final String? gender;

  Kid({
    required String id,
    String? avatar,
    List<String> gallery = const [],
    required this.name,
    this.birth,
    this.gender,
  }) : super(id: id, avatar: avatar, gallery: gallery, type: SubProfileType.kid);

  factory Kid.fromJson(Map<String, dynamic> json) {
    return Kid(
      id: json['id']?.toString() ?? '',
      avatar: json['avatar'],
      gallery: (json['gallery'] as List?)?.map((e) => e.toString()).toList() ?? [],
      name: json['name'] ?? '',
      birth: json['birth'],
      gender: json['gender'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'avatar': avatar,
      'gallery': gallery,
      'type': 'kid',
      'name': name,
      'birth': birth,
      'gender': gender,
    };
  }
}

class Pet extends SubProfile {
  final String name;
  final String? petType; // original type like Dog, Cat
  final String? breed;
  final String? birth;
  final String? gender;

  Pet({
    required String id,
    String? avatar,
    List<String> gallery = const [],
    required this.name,
    this.petType,
    this.breed,
    this.birth,
    this.gender,
  }) : super(id: id, avatar: avatar, gallery: gallery, type: SubProfileType.pet);

  factory Pet.fromJson(Map<String, dynamic> json) {
    return Pet(
      id: json['id']?.toString() ?? '',
      avatar: json['avatar'],
      gallery: (json['gallery'] as List?)?.map((e) => e.toString()).toList() ?? [],
      name: json['name'] ?? '',
      petType: json['pet_type'],
      breed: json['breed'],
      birth: json['birth'],
      gender: json['gender'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'avatar': avatar,
      'gallery': gallery,
      'type': 'pet',
      'name': name,
      'pet_type': petType,
      'breed': breed,
      'birth': birth,
      'gender': gender,
    };
  }
}

class Vehicle extends SubProfile {
  final String brand;
  final String modelName;
  final String? produced;
  final String? nickname;

  Vehicle({
    required String id,
    String? avatar,
    List<String> gallery = const [],
    required this.brand,
    required this.modelName,
    this.produced,
    this.nickname,
  }) : super(id: id, avatar: avatar, gallery: gallery, type: SubProfileType.vehicle);

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id']?.toString() ?? '',
      avatar: json['avatar'],
      gallery: (json['gallery'] as List?)?.map((e) => e.toString()).toList() ?? [],
      brand: json['brand'] ?? '',
      modelName: json['modelname'] ?? '',
      produced: json['produced']?.toString(),
      nickname: json['nickname'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'avatar': avatar,
      'gallery': gallery,
      'type': 'vehicle',
      'brand': brand,
      'modelname': modelName,
      'produced': produced,
      'nickname': nickname,
    };
  }
}
