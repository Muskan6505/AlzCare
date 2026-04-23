import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/shared_widgets.dart';

enum _AuthView { signIn, createAccount }

class AuthScreen extends StatefulWidget {
  final ValueChanged<AppSession> onAuthenticated;

  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _AuthView _view = _AuthView.signIn;
  UserRole _signInRole = UserRole.patient;
  bool _isBusy = false;

  final _signInPatientIdCtrl = TextEditingController();
  final _signInCaregiverIdCtrl = TextEditingController();
  final _createNameCtrl = TextEditingController();
  final _createPatientIdCtrl = TextEditingController();
  final _createCaregiverIdCtrl = TextEditingController();

  @override
  void dispose() {
    _signInPatientIdCtrl.dispose();
    _signInCaregiverIdCtrl.dispose();
    _createNameCtrl.dispose();
    _createPatientIdCtrl.dispose();
    _createCaregiverIdCtrl.dispose();
    super.dispose();
  }

  String _normalizeId(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '_');

  void _showMessage(String message, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? AlzColors.red : AlzColors.green,
        content: Text(message, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Future<void> _signIn() async {
    final patientId = _normalizeId(_signInPatientIdCtrl.text);
    final caregiverId = _normalizeId(_signInCaregiverIdCtrl.text);

    if (patientId.isEmpty) {
      _showMessage('Enter a patient ID to continue.');
      return;
    }

    if (_signInRole == UserRole.caregiver && caregiverId.isEmpty) {
      _showMessage('Enter the caregiver ID linked to this patient.');
      return;
    }

    setState(() => _isBusy = true);
    try {
      final profile = await ApiService.instance.fetchPatientProfile(patientId);
      if (!mounted) return;

      if (profile == null) {
        _showMessage('No patient account was found for "$patientId".');
        return;
      }

      if (_signInRole == UserRole.caregiver) {
        final allowedCaregiverIds = profile.caregiverIds
            .map((id) => _normalizeId(id))
            .where((id) => id.isNotEmpty)
            .toSet();

        if (allowedCaregiverIds.isNotEmpty && !allowedCaregiverIds.contains(caregiverId)) {
          _showMessage('That caregiver ID is not linked to this patient account.');
          return;
        }
      }

      widget.onAuthenticated(
        AppSession(
          role: _signInRole,
          patientId: profile.patientId,
          patientName: profile.name,
          caregiverId: _signInRole == UserRole.caregiver ? caregiverId : null,
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _createAccount() async {
    final patientName = _createNameCtrl.text.trim();
    final patientId = _normalizeId(_createPatientIdCtrl.text);
    final caregiverId = _normalizeId(_createCaregiverIdCtrl.text);

    if (patientName.isEmpty) {
      _showMessage('Enter the patient name.');
      return;
    }

    if (patientId.isEmpty) {
      _showMessage('Enter a patient ID for the new account.');
      return;
    }

    setState(() => _isBusy = true);
    try {
      final existing = await ApiService.instance.fetchPatientProfile(patientId);
      if (!mounted) return;

      if (existing != null) {
        _showMessage(
          'A patient account with ID "$patientId" already exists. Use sign in instead.',
        );
        return;
      }

      final profile = await ApiService.instance.createPatientProfile(
        patientId: patientId,
        name: patientName,
        caregiverIds: caregiverId.isEmpty ? const [] : [caregiverId],
      );
      if (!mounted) return;

      if (profile == null) {
        _showMessage('The account could not be created. Check that the backend is running.');
        return;
      }

      widget.onAuthenticated(
        AppSession(
          role: caregiverId.isEmpty ? UserRole.patient : UserRole.caregiver,
          patientId: profile.patientId,
          patientName: profile.name,
          caregiverId: caregiverId.isEmpty ? null : caregiverId,
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    final panelWidth = wide ? 520.0 : double.infinity;

    return Scaffold(
      backgroundColor: AlzColors.warm,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Wrap(
                spacing: 24,
                runSpacing: 20,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  SizedBox(
                    width: panelWidth,
                    child: Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AlzColors.navy, AlzColors.ocean],
                        ),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: _buildHeroPanel(),
                    ),
                  ),
                  SizedBox(
                    width: panelWidth,
                    child: _buildFormCard(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroPanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.favorite_rounded, color: Colors.white, size: 30),
              SizedBox(width: 12),
              Text(
                'AlzCare AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: 28),
          Text(
            'Patient accounts now start here.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          SizedBox(height: 18),
          Text(
            'Create a patient account from the browser or sign in with an existing patient ID. Caregiver access is linked to the caregiver ID stored on that patient profile.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.6,
            ),
          ),
          SizedBox(height: 28),
          _HeroPoint(
            icon: Icons.person_add_alt_1_rounded,
            text: 'Create a new patient profile using the same backend you already use.',
          ),
          SizedBox(height: 12),
          _HeroPoint(
            icon: Icons.login_rounded,
            text: 'Sign in as a patient or caregiver with backend-backed IDs.',
          ),
          SizedBox(height: 12),
          _HeroPoint(
            icon: Icons.link_rounded,
            text: 'The caregiver dashboard now follows the selected patient instead of the demo account.',
          ),
        ],
      );

  Widget _buildFormCard() => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _viewChip('Sign in', _view == _AuthView.signIn, () {
                  setState(() => _view = _AuthView.signIn);
                }),
                const SizedBox(width: 10),
                _viewChip('Create account', _view == _AuthView.createAccount, () {
                  setState(() => _view = _AuthView.createAccount);
                }),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              _view == _AuthView.signIn ? 'Welcome back' : 'Set up a new patient',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AlzColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _view == _AuthView.signIn
                  ? 'Use the patient ID that already exists in your backend.'
                  : 'This creates a patient profile and optionally links the first caregiver ID.',
              style: const TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 26),
            if (_view == _AuthView.signIn) _buildSignInForm() else _buildCreateForm(),
          ],
        ),
      );

  Widget _buildSignInForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Role',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _roleChip('Patient', UserRole.patient),
              _roleChip('Caregiver', UserRole.caregiver),
            ],
          ),
          const SizedBox(height: 18),
          AlzTextField(
            _signInPatientIdCtrl,
            'Patient ID',
            Icons.badge_outlined,
            hint: 'Example: PATIENT_001',
          ),
          if (_signInRole == UserRole.caregiver) ...[
            const SizedBox(height: 14),
            AlzTextField(
              _signInCaregiverIdCtrl,
              'Caregiver ID',
              Icons.supervisor_account_outlined,
              hint: 'Example: CAREGIVER_001',
            ),
          ],
          const SizedBox(height: 22),
          _submitButton(
            label: _isBusy ? 'Signing in...' : 'Sign in',
            onPressed: _isBusy ? null : _signIn,
          ),
        ],
      );

  Widget _buildCreateForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AlzTextField(
            _createNameCtrl,
            'Patient name',
            Icons.person_outline_rounded,
            hint: 'Example: Robert Wilson',
          ),
          const SizedBox(height: 14),
          AlzTextField(
            _createPatientIdCtrl,
            'Patient ID',
            Icons.badge_outlined,
            hint: 'Example: PATIENT_002',
          ),
          const SizedBox(height: 14),
          AlzTextField(
            _createCaregiverIdCtrl,
            'Caregiver ID (optional)',
            Icons.supervisor_account_outlined,
            hint: 'Leave blank to create patient-only access',
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AlzColors.softBlue.withOpacity(0.55),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'If you add a caregiver ID here, the new account opens in the caregiver dashboard after creation. Otherwise it opens in the patient view.',
              style: TextStyle(fontSize: 13, color: AlzColors.textDark, height: 1.5),
            ),
          ),
          const SizedBox(height: 22),
          _submitButton(
            label: _isBusy ? 'Creating account...' : 'Create account',
            onPressed: _isBusy ? null : _createAccount,
          ),
        ],
      );

  Widget _viewChip(String label, bool selected, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AlzColors.navy : AlzColors.warm,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AlzColors.navy,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );

  Widget _roleChip(String label, UserRole role) => ChoiceChip(
        label: Text(label),
        selected: _signInRole == role,
        onSelected: (_) => setState(() => _signInRole = role),
        selectedColor: AlzColors.navy.withOpacity(0.18),
        labelStyle: TextStyle(
          color: _signInRole == role ? AlzColors.navy : Colors.black54,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      );

  Widget _submitButton({
    required String label,
    required VoidCallback? onPressed,
  }) =>
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            backgroundColor: AlzColors.navy,
            foregroundColor: Colors.white,
          ),
          child: Text(label),
        ),
      );
}

class _HeroPoint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeroPoint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
            ),
          ),
        ],
      );
}
