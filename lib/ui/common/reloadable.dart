import 'package:flutter/material.dart';

import '../../app/services.dart';

/// Loads data asynchronously and reloads it whenever the app's data changes
/// (AppServices.dataChanged), keeping the previous value on screen meanwhile.
class Reloadable<T> extends StatefulWidget {
  const Reloadable({super.key, required this.load, required this.builder, this.loading});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Widget? loading;

  @override
  State<Reloadable<T>> createState() => _ReloadableState<T>();
}

class _ReloadableState<T> extends State<Reloadable<T>> {
  T? _data;
  bool _hasData = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    AppServices.I.dataVersion.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    AppServices.I.dataVersion.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final gen = ++_generation;
    try {
      final d = await widget.load();
      if (!mounted || gen != _generation) return;
      setState(() {
        _data = d;
        _hasData = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && !_hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 8),
            Text('Something went wrong while loading.\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _reload, child: const Text('Try again')),
          ]),
        ),
      );
    }
    if (!_hasData) {
      return widget.loading ?? const Center(child: CircularProgressIndicator());
    }
    return widget.builder(context, _data as T, _reload);
  }
}
