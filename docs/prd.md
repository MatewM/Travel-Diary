# PRD — TaxDays

_(Product Requirements Document. Desarrollar aquí los requisitos del producto.)_
# PRD — TaxDays
**Versión:** 1.0  
**Fecha:** Febrero 2026  
**Estado:** En desarrollo

---

## Qué es TaxDays

Herramienta SaaS para expatriados que automatiza el seguimiento
de días de residencia fiscal por país y año natural.

El problema que resuelve: los expats están obligados a demostrar
ante las autoridades fiscales cuántos días pasaron en cada país.
Hoy lo hacen manualmente, buscando billetes dispersos en emails,
calculando fechas en Excel y generando documentos a mano. Es
tedioso, propenso a errores y estresante.

TaxDays lo automatiza: el usuario sube sus billetes, la app los
lee automáticamente y mantiene un registro siempre actualizado.

---

## Usuario objetivo

Expatriado digital o profesional internacional que:
- Vive entre 2 o más países durante el año
- Necesita justificar su residencia fiscal ante autoridades
- Tiene movilidad frecuente (más de 4-6 viajes/año)
- Valora su tiempo y quiere evitar burocracia

---

## Valor principal

1. **Mínima entrada de datos**: sube el billete, la app extrae
   todo automáticamente via IA (Gemini 2.5 Flash)
2. **Dashboard claro**: sabe en todo momento cuántos días lleva
   en cada país y cuántos le faltan o le quedan
3. **Informe listo para autoridades**: genera el documento
   justificativo con los billetes adjuntos como prueba
4. **Alertas proactivas**: avisa antes de superar 183 días en
   un país o de no llegar al mínimo de residencia fiscal

---

## Funcionalidades — MVP (v1.0)

### Autenticación
- Registro con email + contraseña
- Login con Google (OmniAuth)
- Login con Apple ID (OmniAuth)
- Dashboard privado por usuario, sin acceso cruzado

### Subida y parsing de billetes
- Subir PDF, JPG o PNG (máximo 10MB)
- Extracción automática via Gemini 2.0 Flash:
  aeropuertos, fechas, número de vuelo, aerolínea
- Si el parsing falla: formulario manual de fallback
- Estado visible del billete: procesando / ok / error / manual

### Gestión de viajes
- Creación automática de Trip desde ticket(s) parseados
- Creación manual de viaje (tren, coche, sin billete)
- Edición manual de cualquier campo
- Detección de conflictos: solapamientos, duplicados
- Visualización de huecos (días sin registrar) con botón
  "Añadir período" inline en el dashboard

### Dashboard
- Selector de año natural (por defecto: año actual)
- Tabla completa del año con filas para cada período:
  - Trips registrados (con o sin billete)
  - Gaps (períodos sin registrar, fondo diferenciado)
- Primera fila del año: hereda el último trip del año anterior
  si el usuario estaba en tránsito al 1 de enero
- Por cada país: días acumulados, barra de progreso visual
- Indicadores de color: verde / amarillo / rojo según umbrales
- Panel de alertas fiscales activas

### Informe fiscal
- Seleccionar año y generar PDF
- Contenido: tabla de días por país + lista de billetes
  adjuntos como prueba + períodos sin justificante marcados
- Descarga inmediata

---

## Funcionalidades — Fuera de scope en v1.0

- Soporte multi-moneda o multi-idioma (solo español inicialmente)
- App móvil nativa
- Integración directa con email para importar billetes
- Compartir informe directamente con asesor fiscal
- Soporte para reglas fiscales de más de 10 países inicialmente

---

## Reglas de negocio clave

- Los días en un país se calculan por rangos de trips,
  NO almacenados día a día (ver business_logic.md)
- Límite universal: 183 días = umbral de alerta máxima
- Los trips heredados del año anterior afectan solo a la
  visualización, no modifican los registros del trip original
- Toda la información es privada: un usuario nunca ve
  datos de otro usuario
- Los archivos originales se conservan siempre, incluso
  si el parsing falla

---

## Stack tecnológico

Ver project.mdc — stack completo definido ahí.
Parsing: Google Gemini 2.0 Flash API (free tier).

---

## Criterios de éxito del MVP

- Un usuario puede registrarse, subir 5 billetes y ver su
  dashboard en menos de 10 minutos
- El parsing automático funciona correctamente en >85% de
  los billetes de aerolíneas principales
- El informe PDF generado es válido como justificante
  ante las autoridades fiscales españolas
- Zero acceso cruzado entre usuarios (seguridad crítica)
