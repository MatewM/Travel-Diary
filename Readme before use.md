# Travel-Diary

Aplicación web SaaS para expatriados que automatiza el seguimiento de días de residencia fiscal extrayendo datos de billetes de avión.

## Configuración Rápida

Para poner el proyecto en marcha, sigue estos pasos:

1.  **Clonar el repositorio:**

    git clone https://github.com/tu-usuario/Travel-Diary.git
    cd Travel-Diary
Instalar dependencias de sistema (Ubuntu/Debian):
Necesitas Ruby (3.2+), PostgreSQL, ImageMagick, ZBar, Poppler y herramientas de compilación.
    sudo apt-get update    sudo apt-get install -y ruby-full 
    sudo apt-get install -y imagemagick libzbar-dev
    postgresql imagemagick libzbar-dev zbar-tools poppler-utils build-essential
Instalar gemas de Ruby:
Bundler gestiona las gemas del proyecto.
    gem install bundler    bundle install
Configurar base de datos:
    rails db:create    rails db:migrate    # Opcional: rails db:seed para datos de ejemplo
Variables de entorno:
Crea un archivo .env en la raíz del proyecto para credenciales y claves.
    GOOGLE_CLIENT_ID=tu_id_de_cliente_google    GOOGLE_CLIENT_SECRET=tu_secreto_de_cliente_google    # Añade otras variables necesarias
Iniciar servicios:
Abre dos terminales y ejecuta:
    # Terminal 1 (servidor web)    rails server    # Terminal 2 (tareas en segundo plano)    bundle exec sidekiq
Visita http://localhost:3000 en tu navegador.    