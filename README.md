# Frontend de Gestión de Facturas (Flutter)

Este es el nuevo frontend de la aplicación, reconstruido con Flutter para la web.

## Configuración Inicial Obligatoria

**IMPORTANTE:** Antes de poder ejecutar esta aplicación, debes configurar tus credenciales de Firebase. Este paso es crucial para la seguridad, ya que evita que las claves secretas se almacenen en el control de versiones.

1.  **Crea el archivo de configuración:**
    Dentro de `frontend_flutter/lib/`, crea un nuevo archivo llamado `firebase_options.dart`.

2.  **Añade el siguiente contenido:**
    Copia y pega el siguiente código en el archivo que acabas de crear.

    ```dart
    // File generated manually for the Firebase project.
    // Used by the FlutterFire CLI to initialize Firebase apps.

    import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
    import 'package:flutter/foundation.dart'
        show defaultTargetPlatform, kIsWeb, TargetPlatform;

    class DefaultFirebaseOptions {
      static FirebaseOptions get currentPlatform {
        if (kIsWeb) {
          return web;
        }
        // Since we are only targeting web, we can throw an error for other platforms.
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
          case TargetPlatform.iOS:
          case TargetPlatform.macOS:
          case TargetPlatform.windows:
          case TargetPlatform.linux:
          default:
            throw UnsupportedError(
              'DefaultFirebaseOptions are not supported for this platform.',
            );
        }
      }

      static const FirebaseOptions web = FirebaseOptions(
        // REEMPLAZA ESTOS VALORES CON TUS PROPIAS CREDENCIALES
        apiKey: "TU_API_KEY_AQUI",
        appId: "TU_APP_ID_AQUI",
        messagingSenderId: "TU_MESSAGING_SENDER_ID_AQUI",
        projectId: "TU_PROJECT_ID_AQUI",
        authDomain: "TU_AUTH_DOMAIN_AQUI",
        storageBucket: "TU_STORAGE_BUCKET_AQUI",
        measurementId: "TU_MEASUREMENT_ID_AQUI", // Opcional
      );
    }
    ```

3.  **Reemplaza las credenciales:**
    Sustituye los valores de marcador de posición (`"TU_API_KEY_AQUI"`, etc.) con las credenciales reales de tu proyecto de Firebase. Puedes encontrarlas en la Consola de Firebase > Configuración del Proyecto > Tus aplicaciones > Aplicación web.

El archivo `firebase_options.dart` está incluido en el `.gitignore`, por lo que no se subirá accidentalmente a tu repositorio.
