import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _googleLoading = false;
  bool _appleLoading = false;

  bool get _isLoading => _googleLoading || _appleLoading;

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _googleLoading = true);

    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _googleLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
    } catch (e) {
      setState(() => _googleLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sign in failed: $e')));
      }
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _appleLoading = true);
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);
    OAuthCredential? oauthCredential;

    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
      if (appleCredential.identityToken == null) {
        setState(() => _appleLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Apple Sign-In failed: no identity token received'),
            ),
          );
        }
        return;
      }
      oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );
      debugPrint(
        '[Apple] identityToken length: ${appleCredential.identityToken!.length}',
      );
      debugPrint(
        '[Apple] authorizationCode: ${appleCredential.authorizationCode}',
      );
      debugPrint('[Apple] userIdentifier: ${appleCredential.userIdentifier}');
      // Decode JWT payload (middle segment) to inspect claims
      try {
        final parts = appleCredential.identityToken!.split('.');
        if (parts.length == 3) {
          String payload = parts[1];
          // Pad base64 to multiple of 4
          while (payload.length % 4 != 0) {
            payload += '=';
          }
          final decoded = utf8.decode(base64Url.decode(payload));
          debugPrint('[Apple] JWT payload: $decoded');
        }
      } catch (e) {
        debugPrint('[Apple] Could not decode JWT: $e');
      }
      debugPrint('[Apple] Calling Firebase signInWithCredential...');
      await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      debugPrint('[Apple] Firebase sign-in succeeded');
      // Apple only provides name on the very first sign-in — capture and persist it
      final givenName = appleCredential.givenName;
      final familyName = appleCredential.familyName;
      if (givenName != null || familyName != null) {
        final fullName = [givenName, familyName]
            .where((s) => s != null && s.isNotEmpty)
            .join(' ');
        if (fullName.isNotEmpty) {
          await FirebaseAuth.instance.currentUser?.updateDisplayName(fullName);
        }
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      debugPrint(
        '[Apple] Authorization exception: code=${e.code} message=${e.message}',
      );
      setState(() => _appleLoading = false);
    } on FirebaseAuthException catch (e) {
      debugPrint(
        '[Apple] FirebaseAuthException: code=${e.code} message=${e.message} plugin=${e.plugin}',
      );
      debugPrint('[Apple] FirebaseAuthException stackTrace: ${e.stackTrace}');
      if (e.code == 'account-exists-with-different-credential' &&
          oauthCredential != null) {
        await _linkAppleToGoogle(oauthCredential);
      } else {
        setState(() => _appleLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sign in failed [${e.code}]: ${e.message}')),
          );
        }
      }
    } catch (e, st) {
      debugPrint('[Apple] Unexpected error: $e');
      debugPrint('[Apple] Stack: $st');
      setState(() => _appleLoading = false);
    }
  }

  Future<void> _linkAppleToGoogle(OAuthCredential appleCredential) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Link Accounts',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This Apple ID\'s email is already associated with a Google account. '
          'Sign in with Google to link both accounts — your scan history will be preserved.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sign in with Google',
              style: TextStyle(color: Color(0xFF646CFF)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      setState(() => _appleLoading = false);
      return;
    }

    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _appleLoading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final googleCredential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        googleCredential,
      );
      await userCredential.user!.linkWithCredential(appleCredential);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
    } catch (e) {
      setState(() => _appleLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Account linking failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF242424)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF646CFF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Icon(
                      Icons.directions_run_rounded,
                      size: 48,
                      color: Color(0xFF646CFF),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Sneaker Scanner',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to sync your scans',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _signInWithGoogle,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _googleLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.network(
                                  'https://www.google.com/favicon.ico',
                                  width: 24,
                                  height: 24,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.g_mobiledata, size: 24),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _signInWithApple,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Colors.white24),
                        ),
                      ),
                      child: _appleLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.apple, size: 22, color: Colors.white),
                                SizedBox(width: 12),
                                Text(
                                  'Continue with Apple',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
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
