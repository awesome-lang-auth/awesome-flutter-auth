# Awesome Node Auth - Flutter Integration Example

This example demonstrates a complete authentication flow using the Flutter `awesome_flutter_auth` client library with a Node.js backend powered by `awesome-node-auth`.

The Flutter app in this folder uses a local path dependency (`path: ../`) so it always runs against the current workspace version of `awesome_flutter_auth`, not the published pub.dev version.

## 📱 Architecture

```
┌──────────────────┐         HTTP/REST          ┌──────────────────┐
│  Flutter App     │◄──────────────────────────►│  Node.js Server  │
│  (iOS/Android    │   Web:  HttpOnly Cookies   │ (awesome-node-   │
│   Web / WASM)    │   Native: Bearer Tokens    │   auth)          │
└──────────────────┘                            └──────────────────┘
   • Login / Register                              • Express App
   • Profile Screen                                • In-Memory Store
   • Fetch Protected Data (auth.httpClient)        • Auth Routes
   • Silent Token Refresh                          • Protected Route
```

Authentication strategy is chosen automatically:

| Platform | Strategy |
|---|---|
| Web / WASM | HttpOnly cookie + `X-CSRF-Token` |
| iOS / Android / Desktop | Bearer token via `TokenStorage`, `X-Auth-Strategy: bearer` |

## 🚀 Quick Start

### Prerequisites

- **Flutter 3.5+** ([Install Flutter](https://flutter.dev/docs/get-started/install))
- **Node.js 18+** ([Install Node.js](https://nodejs.org/))
- **Dart 3.5+** (comes with Flutter)

### 1. Start the Node.js Server

```bash
cd example/server

# Install dependencies
npm install

# Start the server (http://localhost:3000)
npm start
```

You should see:
```
╔═══════════════════════════════════════════════════════════╗
║   Awesome Node Auth - Flutter Example Server              ║
║   Running on http://localhost:3000                         ║
╠═══════════════════════════════════════════════════════════╣
║   Test Credentials:                                       ║
║   • Email: demo@example.com                               ║
║   • Password: demo123                                     ║
╚═══════════════════════════════════════════════════════════╝
```

### 2. Run the Flutter App

In a separate terminal:

```bash
cd example

# Get dependencies
flutter pub get

# Run on a device or emulator
flutter run

# Or for web:
flutter run -d chrome
```

## 🧪 Testing

### Using the Demo User

1. **Open the Flutter app** (login screen shows)
2. **Click "Login"**
3. **Enter demo credentials:**
   - Email: `demo@example.com`
   - Password: `demo123`
4. **You'll see the profile screen with your user info**
5. **Click "Logout"** to clear the session

### Creating a New User

1. **Fill email and password** in the login screen
2. **Click "Register"** — the app logs you in automatically after registration
3. **You'll see your profile screen**
4. **Click "Fetch Protected Data"** to call `GET /profile` using `auth.httpClient` — no manual token handling
5. **Click "Logout"** to clear the session

## 🔑 auth.httpClient — interceptor pattern

The example demonstrates the core design principle: once authenticated, your code never touches tokens.

```dart
// In main.dart — one line, works on all platforms:
final response = await authClient.httpClient.get(
  Uri.parse('http://localhost:3000/profile'),
);
```

- On **native**: the library automatically attaches `Authorization: Bearer <token>` and refreshes it silently on 401.
- On **web / WASM**: the browser sends the HttpOnly cookie; the library adds `X-CSRF-Token` for same-origin requests.

This is equivalent to the `AuthInterceptor` in `ng-awesome-node-auth` or the `auth.middleware()` on the Express side.

## 📡 API Endpoints

### Authentication Endpoints

```bash
# Register a new user
POST /auth/register
Content-Type: application/json
{
  "email": "user@example.com",
  "password": "secure-password"
}
# Response: { "id": "123", "email": "user@example.com", ... }

# Login with credentials
POST /auth/login
Content-Type: application/json
{
  "email": "demo@example.com",
  "password": "demo123"
}
# Response: JWT in cookies + refresh token

# Get current user (requires Bearer token)
GET /auth/me
Authorization: Bearer <access-token>
# Response: { "id": "123", "email": "demo@example.com", ... }

# Refresh expired access token
POST /auth/refresh
# Uses refresh token from cookies

# Logout (clears tokens)
POST /auth/logout
```

### Server Info Endpoints

```bash
# Health check
GET http://localhost:3000/health

# Server info + available endpoints
GET http://localhost:3000/info

# Protected route example
GET http://localhost:3000/profile
Authorization: Bearer <access-token>
```

## 🔒 Security Notes

### For Development Only

This example uses:
- **Hardcoded secrets** (change in production via `.env`)
- **In-memory storage** (data lost on server restart)
- **Disabled CSRF** (appropriate for native/mobile Bearer token clients — see note below)
- **HTTP over localhost** (no HTTPS)

> **CSRF note:** The example server sets `csrf: { enabled: false }` to support native
> (iOS/Android/Desktop) clients that authenticate with Bearer tokens. When your Flutter
> **web** app runs against the same server, the `AuthHttpClient` sends an `X-CSRF-Token`
> header but the server currently ignores it. For a production web deployment, enable CSRF
> on the server (`csrf: { enabled: true }`) — `awesome-node-auth` detects the auth strategy
> from the `X-Auth-Strategy` request header and applies CSRF validation only to
> cookie-based (web) sessions.

### For Production

1. **Use strong secrets:**
   ```bash
   export ACCESS_TOKEN_SECRET="your-strong-secret-key"
   export REFRESH_TOKEN_SECRET="your-strong-refresh-key"
   ```

2. **Use a real database** (MongoDB, PostgreSQL, MySQL):
   - See [awesome-node-auth examples](../../examples)

3. **Enable HTTPS** and set `secure: true` in cookies

4. **Implement proper CORS** for your domains

5. **Store credentials in `.env`** file (never commit to git)

## 📂 Project Structure

```
example/
├── lib/
│   └── main.dart              # Flutter app with login/profile/logout
├── pubspec.yaml               # Flutter dependencies
├── server/
│   ├── package.json           # Node.js dependencies
│   ├── server.js              # Express server + awesome-node-auth
│   └── README.md              # This file
└── android/
└── ios/
└── web/
```

## 🛠️ Customization

### Change Server URL

In [lib/main.dart](lib/main.dart), modify:

```dart
late final AuthClient authClient = AuthClient(
  AuthOptions(
    apiPrefix: 'https://your-api.example.com/auth', // Change this
    headless: true,
  ),
);
```

### Use auth.httpClient for your own backend calls

```dart
// Anywhere in your widget tree, after authentication:
final response = await authClient.httpClient.get(
  Uri.parse('https://your-api.example.com/todos'),
);
```

No token management required — the client injects credentials transparently.

### Add More API Endpoints

In [server/server.js](server/server.js):

```javascript
// Example: GET user by ID
app.get('/api/users/:id', auth.middleware(), (req, res) => {
  const userId = req.params.id;
  const user = userStore.findById(userId);
  res.json(user);
});
```

### Store User Data

The in-memory store is initialized as:

```javascript
const userStore = new InMemoryUserStore();

// Pre-populate demo user
const testUser = await userStore.create({
  email: 'demo@example.com',
  password: await passwordService.hash('demo123'),
});
```

To use MongoDB or another database, implement the `IUserStore` interface from `awesome-node-auth`.

## 📚 Learn More

- **Flutter Client:** [awesome_flutter_auth on pub.dev](https://pub.dev/packages/awesome_flutter_auth)
- **Node.js Server:** [awesome-node-auth on npm](https://www.npmjs.com/package/awesome-node-auth)
- **Flutter Docs:** [flutter.dev](https://flutter.dev/docs)
- **awesome-node-auth Docs:** [github.com/awesome-lang-auth/awesome-node-auth](https://github.com/awesome-lang-auth/awesome-node-auth)

## 🐛 Troubleshooting

### "Connection refused" in Flutter app

- Make sure server is running: `npm start` in `example/server/`
- Check server is on `http://localhost:3000`
- On mobile device, use your computer's IP instead of `localhost`

### "Port 3000 already in use"

```bash
# Kill process on port 3000
lsof -ti:3000 | xargs kill -9

# Or use a different port
PORT=3001 npm start
```

### Flutter app crashes on login

- Check browser console for CORS errors
- Verify server logs for auth errors
- Ensure credentials match exactly

### CORS errors

The server allows any `localhost` or `127.0.0.1` origin on any port (regex-based, suitable for development).

For production, pin the allowed origins in [server/server.js](server/server.js):

```javascript
app.use(cors({
  origin: ['https://your-app.example.com'],
  credentials: true,
}));
```

## 📄 License

This example is part of [awesome-flutter-auth](https://github.com/awesome-lang-auth/awesome-flutter-auth) and is licensed under the MIT License.
