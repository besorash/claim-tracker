/// Insurance company reference (spec §13 suggested table). Used for
/// autocomplete in forms; claims store the name as free text so data remains
/// valid even if a company row is later removed.
library;

class InsuranceCompany {
  const InsuranceCompany({required this.id, required this.name});

  final int id;
  final String name;

  Map<String, Object?> toRow() => <String, Object?>{'id': id, 'name': name};

  factory InsuranceCompany.fromRow(Map<String, Object?> row) =>
      InsuranceCompany(id: row['id']! as int, name: row['name']! as String);
}
