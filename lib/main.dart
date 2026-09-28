import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// A placeholder until the design's screens land; the navy, the wordmark and
// the byline are the design's splash typography without its mark or bar.
const _navy = Color(0xFF05285F);
const _teal = Color(0xFF00D6B4);
const _byline = Color(0xFF7FA6D8);

void main() {
  runApp(const HonestChessApp());
}

class HonestChessApp extends StatelessWidget {
  const HonestChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Honest Chess',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _navy,
      ),
      home: const PlaceholderScreen(),
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _navy,
      ),
      child: Scaffold(
        backgroundColor: _navy,
        body: SafeArea(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: 'Honest Chess',
                    excludeSemantics: true,
                    child: const Text.rich(
                      TextSpan(
                        text: 'Honest',
                        children: [
                          TextSpan(
                            text: 'Chess',
                            style: TextStyle(color: _teal),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'BY HONEST ARCADE',
                    style: TextStyle(
                      color: _byline,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 3,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
