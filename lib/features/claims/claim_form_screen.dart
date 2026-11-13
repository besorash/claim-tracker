/// Claim add/edit form (spec §7) — sections per §7.1–§7.4, Arabic validation
/// messages from `S.*`, and input preservation on a failed save (Review Focus
/// #1): the screen never clears or rebuilds controllers when validation fails.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/accident_types.dart';
import '../../core/constants/insurers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/claim.dart';
import '../../core/models/claim_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import 'claim_form_model.dart';

class ClaimFormScreen extends StatefulWidget {
  const ClaimFormScreen({super.key, this.claim, required this.onSaved});

  /// `null` → add mode; otherwise edit mode for this claim.
  final Claim? claim;

  /// Called exactly once with the built [Claim] when validation passes, and
  /// awaited before the form closes — so a failed persist keeps the user in
  /// the form (spec §7). The screen does NOT touch the repository: the shell
  /// wires persistence. `FutureOr` lets callers return either void or a
  /// Future (e.g. `_claims.create(c)`).
  final FutureOr<void> Function(Claim claim) onSaved;

  @override
  State<ClaimFormScreen> createState() => _ClaimFormScreenState();
}

class _ClaimFormScreenState extends State<ClaimFormScreen> {
  final ClaimFormModel _model = ClaimFormModel();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _errors = {};

  static const List<String> _textFields = [
    'customerName',
    'mobile',
    'nationalId',
    'email',
    'vehicleType',
    'city',
    'plate',
    'claimNumber',
    'custInsurer',
    'insurerRef',
    'amount',
    'notes',
  ];

  /// Selected entry of the insurer list: a listed company's stored name,
  /// [_otherInsurer] for a typed-in company, or null when nothing is chosen.
  String? _insurerChoice;
  static const String _otherInsurer = '__other__';

  /// Selected accident type: one of [AccidentTypes]' stored English names,
  /// or null when unset. A legacy free-form value (the field used to be free
  /// text) starts unselected and stays in the model until the user picks an
  /// entry — selecting "Not set" clears it.
  String? _accidentTypeChoice;

  @override
  void initState() {
    super.initState();
    final Claim? existing = widget.claim;
    if (existing != null) _model.loadFrom(existing);
    // A stored company from the list selects it (whatever its spelling); any
    // other stored name opens under "Other" with the text kept.
    final String stored = _model.customerInsuranceCompany.trim();
    final Insurer? listed = Insurers.match(stored);
    if (listed != null) {
      _insurerChoice = listed.en;
      _model.customerInsuranceCompany = listed.en;
    } else if (stored.isNotEmpty) {
      _insurerChoice = _otherInsurer;
    }
    // A stored accident type pre-selects its listed entry when it matches one
    // of the fixed options; a legacy free-form value starts unselected and is
    // kept in the model until the user chooses an entry.
    _accidentTypeChoice = AccidentTypes.match(_model.accidentType)?.en;
    for (final String key in _textFields) {
      _controllers[key] = TextEditingController(text: _valueFor(key));
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _valueFor(String key) => switch (key) {
    'customerName' => _model.customerName,
    'mobile' => _model.customerMobile,
    'nationalId' => _model.customerNationalId,
    'email' => _model.customerEmail,
    'vehicleType' => _model.vehicleType,
    'city' => _model.accidentCity,
    'plate' => _model.vehiclePlate,
    'claimNumber' => _model.claimNumber,
    'custInsurer' => _model.customerInsuranceCompany,
    'insurerRef' => _model.insurerReferenceNumber,
    'amount' => _model.claimAmount,
    'notes' => _model.notes,
    _ => '',
  };

  void _onChanged(String key, String value) {
    switch (key) {
      case 'customerName':
        _model.customerName = value;
      case 'mobile':
        _model.customerMobile = value;
      case 'nationalId':
        _model.customerNationalId = value;
      case 'email':
        _model.customerEmail = value;
      case 'vehicleType':
        _model.vehicleType = value;
      case 'city':
        _model.accidentCity = value;
      case 'plate':
        _model.vehiclePlate = value;
      case 'claimNumber':
        _model.claimNumber = value;
      case 'custInsurer':
        _model.customerInsuranceCompany = value;
      case 'insurerRef':
        _model.insurerReferenceNumber = value;
      case 'amount':
        _model.claimAmount = value;
      case 'notes':
        _model.notes = value;
    }
  }

  Future<void> _pickDate(String which) async {
    final DateTime? current = which == 'accident'
        ? _model.accidentDateUtcMs
        : _model.submissionDateUtcMs;
    final DateTime now = DateTime.now().toUtc();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: (current ?? now).toLocal(),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    final DateTime utc = picked.toUtc();
    setState(() {
      if (which == 'accident') {
        _model.accidentDateUtcMs = utc;
      } else {
        _model.submissionDateUtcMs = utc;
      }
      _errors[which] = null;
    });
  }

  Future<void> _pickFollowUp() async {
    final DateTime now = DateTime.now().toUtc();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: (_model.nextFollowUpUtcMs ?? now).toLocal(),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() => _model.nextFollowUpUtcMs = picked.toUtc());
  }

  Future<void> _save() async {
    final Map<String, String?> errors = <String, String?>{
      'customerName': _model.validateCustomerName(),
      'mobile': _model.validateMobile(),
      'custInsurer': _model.validateCustomerInsurer(),
      'plate': _model.validateVehiclePlate(),
      'vehicleType': _model.validateVehicleType(),
      'accident': _model.accidentDateUtcMs == null ? S.requiredField : null,
    };

    if (errors.values.any((String? e) => e != null)) {
      // Validation failed: show inline errors and keep ALL typed input intact.
      setState(() => _errors.addAll(errors));
      return;
    }

    final DateTime nowUtc = DateTime.now().toUtc();
    final Claim claim = widget.claim == null
        ? _model.buildNew(nowUtc)
        : _model.applyTo(widget.claim!, nowUtc);

    // Await the caller's persist: only close once it has completed, so a
    // failed save keeps the user in the form with all input intact (spec §7).
    await widget.onSaved(claim);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.claim == null ? S.addClaim : S.edit)),
      // Eager (non-lazy) form: every field must exist in the tree at once so
      // all validation errors render and tests can address any field directly.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _section(S.sectionCustomerInfo, [
              _field(
                'customerName',
                label: S.customerNameLabel,
                required: true,
              ),
              _field('mobile', label: S.mobileLabel, number: true),
              _field('nationalId', label: S.nationalIdLabel),
              _field('email', label: S.emailLabel),
            ]),
            _section(S.sectionAccidentInfo, [
              _dateRow(
                which: 'accident',
                label: S.accidentDateLabel,
                value: _model.accidentDateUtcMs,
                required: true,
              ),
              _field('city', label: S.cityLabel),
              _accidentTypeField(),
              _field('plate', label: S.vehiclePlateLabel, required: true),
              _field('vehicleType', label: S.vehicleTypeLabel, required: true),
              _liabilityField(),
            ]),
            _section(S.sectionClaimInfo, [
              _field('claimNumber', label: S.claimNumberLabel),
              _insurerField(),
              _dateRow(
                which: 'submission',
                label: S.submissionDateLabel,
                value: _model.submissionDateUtcMs,
              ),
              _field('insurerRef', label: S.insurerRefLabel),
              _field('amount', label: S.claimAmountLabel, number: true),
              _field('notes', label: S.notesLabel, multiline: true),
            ]),
            _section(S.nextFollowUpLabel, [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const Key('date-followup'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: _pickFollowUp,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 18,
                              color: AppTheme.muted(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _model.nextFollowUpUtcMs == null
                                    ? S.setNextFollowUp
                                    : TimeUtils.formatDate(
                                        _model.nextFollowUpUtcMs!,
                                      ),
                                style: TextStyle(
                                  color: _model.nextFollowUpUtcMs == null
                                      ? AppTheme.muted(context)
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_model.nextFollowUpUtcMs != null)
                    TextButton(
                      onPressed: () =>
                          setState(() => _model.nextFollowUpUtcMs = null),
                      child: const Icon(Icons.clear, size: 18),
                    ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.statusLabel,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        DropdownButton<String>(
                          value: _model.statusKey,
                          isExpanded: true,
                          items: [
                            for (final meta in ClaimStatus.all)
                              DropdownMenuItem(
                                value: meta.key,
                                child: Text(meta.label),
                              ),
                          ],
                          onChanged: (String? key) {
                            if (key != null) {
                              setState(() => _model.statusKey = key);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.notifications_off, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      S.reminderDisabled,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.muted(context),
                      ),
                    ),
                  ),
                ],
              ),
            ]),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(S.cancel),
              ),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 48),
                  ),
                  child: Text(S.save),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String key, {
    required String label,
    bool required = false,
    bool number = false,
    bool multiline = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: Key('field-$key'),
        controller: _controllers[key],
        keyboardType: number ? TextInputType.number : null,
        maxLines: multiline ? null : 1,
        onChanged: (String v) => _onChanged(key, v),
        decoration: InputDecoration(
          labelText: label,
          errorText: _errors[key],
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  /// Insurer list in the app's language, plus "Other" to type a company that
  /// is not listed. The claim stores the listed company's English name.
  Widget _insurerField() {
    final bool other = _insurerChoice == _otherInsurer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InputDecorator(
            key: const Key('field-insurerChoice'),
            decoration: InputDecoration(
              labelText: S.customerInsurerLabel,
              errorText: other ? null : _errors['custInsurer'],
              border: const OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                value: _insurerChoice,
                items: <DropdownMenuItem<String>>[
                  for (final Insurer i in Insurers.all)
                    DropdownMenuItem<String>(
                      value: i.en,
                      child: Text(i.label, overflow: TextOverflow.ellipsis),
                    ),
                  DropdownMenuItem<String>(
                    value: _otherInsurer,
                    child: Text(S.insurerOther),
                  ),
                ],
                onChanged: (String? v) => setState(() {
                  _insurerChoice = v;
                  _errors['custInsurer'] = null;
                  if (v == _otherInsurer) {
                    // Start from whatever was typed before, not a list name.
                    final String typed = _controllers['custInsurer']!.text;
                    _model.customerInsuranceCompany =
                        Insurers.match(typed) == null ? typed : '';
                    _controllers['custInsurer']!.text =
                        _model.customerInsuranceCompany;
                  } else if (v != null) {
                    _model.customerInsuranceCompany = v;
                  }
                }),
              ),
            ),
          ),
          if (other) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('field-custInsurer'),
              controller: _controllers['custInsurer'],
              onChanged: (String v) => _onChanged('custInsurer', v),
              decoration: InputDecoration(
                labelText: S.insurerOtherLabel,
                errorText: _errors['custInsurer'],
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Accident type as a fixed list (spec §7.2): one of [AccidentTypes], or
  /// unset — same shape as the liability dropdown. The claim stores the listed
  /// entry's English name; its label is shown in the app's language.
  Widget _accidentTypeField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        key: const Key('field-accidentType'),
        decoration: InputDecoration(
          labelText: S.accidentTypeLabel,
          border: const OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            isExpanded: true,
            value: _accidentTypeChoice,
            items: <DropdownMenuItem<String?>>[
              DropdownMenuItem<String?>(
                value: null,
                child: Text(S.liabilityNotSet),
              ),
              for (final AccidentType t in AccidentTypes.all)
                DropdownMenuItem<String?>(
                  value: t.en,
                  child: Text(t.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (String? v) => setState(() {
              _accidentTypeChoice = v;
              // Selecting an entry stores its English name; "Not set" clears
              // the field (including any legacy free-form value).
              _model.accidentType = v ?? '';
            }),
          ),
        ),
      ),
    );
  }

  /// Optional liability share: not set, 0%, 25%, 50%, 75% or 100%.
  Widget _liabilityField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        key: const Key('field-liability'),
        decoration: InputDecoration(
          labelText: S.liabilityPercentLabel,
          border: const OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<double?>(
            isExpanded: true,
            value: _model.liabilityPercent,
            items: <DropdownMenuItem<double?>>[
              DropdownMenuItem<double?>(
                value: null,
                child: Text(S.liabilityNotSet),
              ),
              for (final double option in ClaimFormModel.liabilityOptions)
                DropdownMenuItem<double?>(
                  value: option,
                  child: Text('${option.toStringAsFixed(0)}%'),
                ),
            ],
            onChanged: (double? v) =>
                setState(() => _model.liabilityPercent = v),
          ),
        ),
      ),
    );
  }

  Widget _dateRow({
    required String which,
    required String label,
    DateTime? value,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: Key('date-$which'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => _pickDate(which),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                errorText: _errors[which],
                border: const OutlineInputBorder(),
                suffixIcon: const Icon(Icons.calendar_today),
              ),
              child: Text(value == null ? '' : TimeUtils.formatDate(value)),
            ),
          ),
        ],
      ),
    );
  }
}
