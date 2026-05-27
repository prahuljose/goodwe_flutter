import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../data/models/tapo_device.dart';
import '../../data/repositories/tapo_local_repository.dart';
import 'consumption_provider.dart';

const _consumptionColor = Color(0xFF38BDF8);

class TapoDevicesScreen extends StatefulWidget {
  const TapoDevicesScreen({super.key});

  @override
  State<TapoDevicesScreen> createState() => _TapoDevicesScreenState();
}

class _TapoDevicesScreenState extends State<TapoDevicesScreen> {
  late TapoLocalRepository _repo;
  bool _hasAccount = false;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo = context.read<ConsumptionProvider>().repo;
    _load();
  }

  Future<void> _load() async {
    _hasAccount = await _repo.hasAccount();
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Tapo Plugs',
            style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _consumptionColor))
          : _hasAccount
              ? _DeviceList(repo: _repo, onChanged: () => setState(() {}))
              : _AccountForm(
                  repo: _repo,
                  onSaved: () => setState(() => _hasAccount = true),
                ),
    );
  }
}

// ─── Account credentials form ─────────────────────────────────────────────────

class _AccountForm extends StatefulWidget {
  final TapoLocalRepository repo;
  final VoidCallback onSaved;
  const _AccountForm({required this.repo, required this.onSaved});

  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await widget.repo.setAccount(_emailCtrl.text.trim(), _passCtrl.text);
    if (mounted) {
      setState(() => _saving = false);
      widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoBanner(
              text: 'Enter your TP-Link / Tapo account — the same login you use '
                  'in the Tapo app. You\'ll add individual plugs next.',
            ),
            const SizedBox(height: 28),
            _label('Tapo Account Email'),
            const SizedBox(height: 8),
            _field(
              controller: _emailCtrl,
              hint: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 20),
            _label('Tapo Account Password'),
            const SizedBox(height: 8),
            _field(
              controller: _passCtrl,
              hint: '••••••••',
              obscure: _obscure,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.textSecondary, size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              validator: (v) =>
                  (v == null || v.length < 6) ? 'Password too short' : null,
            ),
            const SizedBox(height: 32),
            _PrimaryButton(
              label: 'Continue',
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Device list ──────────────────────────────────────────────────────────────

class _DeviceList extends StatefulWidget {
  final TapoLocalRepository repo;
  final VoidCallback onChanged;
  const _DeviceList({required this.repo, required this.onChanged});

  @override
  State<_DeviceList> createState() => _DeviceListState();
}

class _DeviceListState extends State<_DeviceList> {
  @override
  Widget build(BuildContext context) {
    final devices = widget.repo.devices;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _InfoBanner(
                text: 'Your phone must be on the same Wi-Fi as the plugs, and '
                    '"Third-Party Compatibility" must be ON in the Tapo app.',
              ),
              const SizedBox(height: 20),
              if (devices.isEmpty)
                _EmptyDevices()
              else
                ...devices.map((d) => _DeviceTile(
                      device: d,
                      onRename: () => _rename(d),
                      onDelete: () => _delete(d),
                    )),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: _PrimaryButton(
            label: 'Add a plug',
            icon: Icons.add_rounded,
            onPressed: _addFlow,
          ),
        ),
      ],
    );
  }

  Future<void> _addFlow() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddDeviceSheet(repo: widget.repo),
    );
    if (added == true && mounted) {
      setState(() {});
      widget.onChanged();
      context.read<ConsumptionProvider>().reload();
    }
  }

  Future<void> _rename(TapoDevice d) async {
    final ctrl = TextEditingController(text: d.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Rename plug',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Plug name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Save',
                style: TextStyle(color: _consumptionColor)),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await widget.repo.renameDevice(d.id, name);
      if (mounted) {
        setState(() {});
        widget.onChanged();
        context.read<ConsumptionProvider>().reload();
      }
    }
  }

  Future<void> _delete(TapoDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Remove plug?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text('Stop tracking "${d.name}"?',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.repo.removeDevice(d.id);
      if (mounted) {
        setState(() {});
        widget.onChanged();
        context.read<ConsumptionProvider>().reload();
      }
    }
  }
}

class _DeviceTile extends StatelessWidget {
  final TapoDevice device;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _DeviceTile({
    required this.device,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _consumptionColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.power_rounded,
                color: _consumptionColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${device.model} · ${device.ip}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                color: AppColors.textSecondary, size: 18),
            onPressed: onRename,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.red, size: 18),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: const [
          Icon(Icons.power_off_rounded, color: AppColors.textSecondary, size: 36),
          SizedBox(height: 12),
          Text('No plugs added yet',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          SizedBox(height: 4),
          Text('Add your first Tapo plug below',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

// ─── Add device bottom sheet ──────────────────────────────────────────────────

class _AddDeviceSheet extends StatefulWidget {
  final TapoLocalRepository repo;
  const _AddDeviceSheet({required this.repo});

  @override
  State<_AddDeviceSheet> createState() => _AddDeviceSheetState();
}

class _AddDeviceSheetState extends State<_AddDeviceSheet> {
  final _ipCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _probing = false;
  bool _saving = false;
  String? _error;
  TapoDevice? _found;

  @override
  void dispose() {
    _ipCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final ip = _ipCtrl.text.trim();
    if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(ip)) {
      setState(() => _error = 'Enter a valid IPv4 address');
      return;
    }
    setState(() {
      _probing = true;
      _error = null;
      _found = null;
    });
    try {
      final device = await widget.repo.probe(ip);
      setState(() {
        _found = device;
        _nameCtrl.text = device.name; // pre-fill auto name (editable)
        _probing = false;
      });
    } on TapoLocalException catch (e) {
      setState(() {
        _error = e.message;
        _probing = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _probing = false;
      });
    }
  }

  Future<void> _save() async {
    final found = _found;
    if (found == null) return;
    setState(() => _saving = true);
    final name = _nameCtrl.text.trim().isEmpty ? found.name : _nameCtrl.text.trim();
    await widget.repo.addDevice(found.copyWith(name: name));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Add a plug',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _label('Plug IP Address'),
            const SizedBox(height: 8),
            _field(
              controller: _ipCtrl,
              hint: '192.168.0.100',
              keyboardType: TextInputType.number,
              enabled: _found == null,
            ),
            const SizedBox(height: 6),
            const Text('Tapo app → plug → ⚙ → Device Info → IP Address',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),

            if (_error != null) ...[
              const SizedBox(height: 14),
              _ErrorBox(_error!),
            ],

            // After probe: show fetched identity + editable name
            if (_found != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: AppColors.green.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded,
                        color: AppColors.green, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Found ${_found!.model} — “${_found!.name}”',
                          style: const TextStyle(
                              color: AppColors.green, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _label('Name'),
              const SizedBox(height: 8),
              _field(controller: _nameCtrl, hint: 'Plug name'),
            ],

            const SizedBox(height: 24),
            _found == null
                ? _PrimaryButton(
                    label: 'Find plug',
                    loading: _probing,
                    onPressed: _probe,
                  )
                : _PrimaryButton(
                    label: 'Add plug',
                    loading: _saving,
                    onPressed: _save,
                  ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final String text;
  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _consumptionColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _consumptionColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: _consumptionColor, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: AppColors.red, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool loading;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _consumptionColor,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
      ),
    );
  }
}

Widget _label(String text) => Text(text,
    style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w500));

Widget _field({
  required TextEditingController controller,
  required String hint,
  TextInputType? keyboardType,
  bool obscure = false,
  bool enabled = true,
  Widget? suffixIcon,
  String? Function(String?)? validator,
}) {
  return TextFormField(
    controller: controller,
    obscureText: obscure,
    enabled: enabled,
    keyboardType: keyboardType,
    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
    validator: validator,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.cardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _consumptionColor, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
