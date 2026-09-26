import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:awesome_flutter_auth/awesome_flutter_auth.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Awesome Node Auth - Flutter Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthScreen(),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Initialize auth client pointing to your Node.js server
  late final AuthClient authClient = AuthClient(
    AuthOptions(
      apiPrefix: 'http://localhost:3000/auth', // Change to your server URL
      headless: true, // Don't auto-redirect on session expiry
    ),
  );

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _privateData; // result of a protected API call via auth.httpClient

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await authClient.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (!result.success) {
        setState(() => _errorMessage = result.error ?? 'Login failed');
      }
      // state.userStream will emit the new user, triggering rebuild via listener
    } catch (e) {
      setState(() => _errorMessage = 'Login failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRegister() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await authClient.register(
        _emailController.text.trim(),
        _passwordController.text,
        'User', // firstName
        'Demo', // lastName
      );
      if (!result.success) {
        setState(() => _errorMessage = result.error ?? 'Registration failed');
      } else {
        final loginResult = await authClient.login(
          _emailController.text.trim(),
          _passwordController.text,
        );
        if (!loginResult.success) {
          setState(
            () => _errorMessage =
                loginResult.error ?? 'Login after registration failed',
          );
        }
      }
      // Registration flow authenticated using AuthClient only (no manual token handling)
    } catch (e) {
      setState(() => _errorMessage = 'Registration failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    try {
      await authClient.logout();
      if (mounted) {
        _emailController.clear();
        _passwordController.clear();
        setState(() {
          _errorMessage = null;
          _privateData = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Logout failed: $e');
      }
    }
  }

  /// Demonstrates [AuthClient.httpClient] as a transparent auth interceptor:
  /// no tokens are handled here — the library injects Bearer (native) or
  /// CSRF+cookies (web/WASM) automatically.
  Future<void> _fetchPrivateData() async {
    setState(() => _isLoading = true);
    try {
      // auth.httpClient is a drop-in http.Client with auth injected.
      // On native: adds Authorization + X-Auth-Strategy: bearer.
      // On web/WASM: browser sends HttpOnly cookie automatically.
      final uri = Uri.parse('http://localhost:3000/profile');
      final response = await authClient.httpClient.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() => _privateData = data['message']?.toString());
      } else {
        setState(() => _privateData = 'Error ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _privateData = 'Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // Listen to auth state changes to trigger rebuilds
    authClient.state.userStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = authClient.state.currentUser;

    // Show profile screen if logged in
    if (user != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('User Profile'), centerTitle: true),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircleAvatar(
                radius: 50,
                child: Icon(Icons.person, size: 50),
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome!',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(user.email, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 8),
              if (user.id != null)
                Text(
                  'ID: ${user.id}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _fetchPrivateData,
                icon: const Icon(Icons.cloud_download),
                label: const Text('Fetch Protected Data'),
              ),
              if (_privateData != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    border: Border.all(color: Colors.green),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _privateData!,
                    style: TextStyle(color: Colors.green.shade900),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleLogout,
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
              ),
            ],
          ),
        ),
      );
    }

    // Show login/register screen if not logged in
    return Scaffold(
      appBar: AppBar(title: const Text('Awesome Node Auth'), centerTitle: true),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  Icon(
                    Icons.lock_outline,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Authentication Example',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                  if (_errorMessage != null) const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock),
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Login'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _handleRegister,
                      child: const Text('Register'),
                    ),
                  ),
                  const SizedBox(height: 60),
                  Text(
                    'Make sure the Node.js server is running on http://localhost:3000',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
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
