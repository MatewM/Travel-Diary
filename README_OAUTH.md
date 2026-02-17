# Configuración OAuth y Encriptación

## 1. Google OAuth

1. Ve a [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
2. Crea un proyecto o selecciona uno existente
3. Crea credenciales "ID de cliente de aplicación web"
4. Añade URI de redirección autorizado: `http://localhost:3000/users/auth/google_oauth2/callback`
5. Añade a tu `.env`:

```
GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=xxx
```

## 2. Encriptación de tokens OAuth

Los tokens se guardan encriptados en la base de datos. Ejecuta:

```bash
bin/rails db:encryption:init
```

Añade la salida a tus credentials:

```bash
EDITOR="code --wait" bin/rails credentials:edit
```

O añade a `.env` las variables:

```
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=...
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=...
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=...
```

## 3. Apple Sign In (opcional)

Requiere cuenta Apple Developer. Añade a `.env`:

```
APPLE_CLIENT_ID=com.tuapp.service
APPLE_TEAM_ID=...
APPLE_KEY_ID=...
APPLE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
```
