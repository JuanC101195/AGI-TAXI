# Próximo proyecto: Prueba de esfuerzo del sistema Asterisk

> **Curso:** Seminario de Voz IP — proyecto a continuación del AGI Taxi
> **Equipo:** Ana María Garzón Giraldo · Juan Esteban Cardozo Rivera · Víctor Manuel Restrepo Torres
> **Estado:** propuesta planificada · pendiente de ejecución

---

## 1. Enunciado del proyecto

> _"Dado un sistema Asterisk, determinar cuántas extensiones y/o troncales es capaz de soportar simultáneamente manteniendo un nivel aceptable de calidad en las llamadas."_

Keywords del enunciado: **sip stress tests**.

## 2. Por qué elegimos éste (vs los otros 6)

Comparamos los 7 proyectos disponibles del curso y este es el que **maximiza la reutilización** de lo que ya construimos en el AGI Taxi sin requerir hardware físico adicional.

| # | Proyecto alternativo | Reuso estimado | Bloqueador |
|---|---|---|---|
| 7 | VoIP + líneas análogas (con AGI) | 75% | Requiere FXS/FXO físicos del LIS |
| **1** | **Stress test (este)** | **60%** | **Ninguno — solo software** |
| 3 | Llamadas seguras (SRTP) | 50% | Conceptual, menos código nuevo |
| 5 | Asterisk en la nube | 50% | Requiere cuenta cloud (costo) |
| 4 | Integración con CRM | 40% | CRM nuevo (vtiger/zurmo) |
| 2 | Hacking VoIP | 40% | Diferente foco (offensive) |
| 6 | Asterisk embebido | 30% | Hardware ARM físico |

## 3. Qué reusamos del AGI Taxi (ya hecho)

- ✅ **Asterisk 20.19.0 LTS compilado** sobre Debian 13 — `build-asterisk.sh`
- ✅ **VM optimizada** (4 CPUs, 2 GB RAM, host-only IP fija)
- ✅ **`pjsip.conf`** con transport, endpoints, auth — fácil escalar a 100+ usuarios
- ✅ **`extensions.conf`** con dialplan funcional
- ✅ **`taxi_agi.py`** ← oro puro: cada llamada hace I/O real (SQLite + playback de WAV), o sea genera **carga representativa**, no carga sintética vacía
- ✅ **MicroSIP** para llamadas manuales de validación durante el desarrollo

## 4. Qué hay que sumar (esfuerzo: 1-2 días)

| Componente | Para qué | Tiempo estimado |
|---|---|---|
| **SIPp** (sipp.sourceforge.net) | Generador de carga SIP que simula N llamadas concurrentes | 1 h instalar + 2-3 h leer docs |
| **Escenarios XML** | Definen el comportamiento de cada llamada simulada (ej: marca `100`, espera 30 s, cuelga) | 2-3 h |
| **Audio de prueba** (`.pcap`) | Lo que SIPp "habla" durante la llamada | 30 min |
| **Scripts de medición** | Captura CPU/RAM/concurrent calls cada N segundos durante el test | 1-2 h (bash o Python) |
| **Análisis de calidad** | tcpdump → Wireshark CLI para extraer jitter, packet loss, MOS | 2-3 h |
| **Reporte / gráficas** | CSV → matplotlib o Excel para mostrar la curva de degradación | 2-3 h |
| **Documento final** | PDF con metodología + resultados + conclusiones | 3-4 h |

**Total: ~15-20 horas de trabajo distribuidas en 2-3 días.**

## 5. Plan experimental

### 5.1. Métricas a medir

| Categoría | Métricas |
|---|---|
| **Recursos del servidor** | %CPU, RAM usada, file descriptors abiertos, throughput de red |
| **Capacidad** | Llamadas concurrentes (CC), llamadas por segundo (CPS) |
| **Calidad de llamada** | MOS estimado (E-model), jitter (ms), packet loss (%), RTT |
| **Fallos** | Llamadas no establecidas, llamadas cortadas, tasa de errores SIP |

### 5.2. Curva de saturación (test principal)

```
Test 1: 10 llamadas concurrentes  → medir métricas durante 5 min
Test 2: 50 llamadas concurrentes  → 5 min
Test 3: 100 llamadas concurrentes → 5 min
Test 4: 200 llamadas concurrentes → 5 min
Test 5: 300 llamadas concurrentes → 5 min
... hasta encontrar el punto donde MOS < 3.5 o CPU = 100%
```

Resultado: gráfica de **CC en X** vs **CPU/MOS/dropped calls en Y**.

### 5.3. Comparación de carga "fácil" vs "real"

Correr la curva contra **dos extensiones distintas** y comparar:

- **Extensión 600 (echo test)** — carga liviana, solo loopback de RTP
- **Extensión 100 (AGI Taxi)** — carga realista con DB query + playback múltiple

La diferencia muestra **cuánto cuesta la lógica de negocio** vs solo SIP/RTP.

### 5.4. Variación de troncales (opcional / extra)

Si queda tiempo, repetir el test pero entre **dos servidores Asterisk** conectados por un trunk IAX2, midiendo cuántos canales soporta el trunk antes de degradar.

## 6. Topología propuesta

```
┌──────────────────────┐        ┌──────────────────────┐
│  VM 1 - Generador    │  SIP   │  VM 2 - Asterisk     │
│  (load testing)      │  + RTP │  bajo prueba         │
│                      │ ─────> │  (la actual del      │
│  - SIPp              │        │   proyecto AGI)      │
│  - tcpdump (captura) │        │                      │
│                      │        │  192.168.56.10       │
└──────────────────────┘        └──────────────────────┘
                                        │
                                        │ logs + métricas
                                        ▼
                                ┌──────────────────────┐
                                │  Carpeta de reporte  │
                                │  - cpu.csv           │
                                │  - mem.csv           │
                                │  - calls.csv         │
                                │  - quality.csv       │
                                │  - graficas.png      │
                                └──────────────────────┘
```

## 7. Decisiones a tomar antes de arrancar

1. **¿VM separada para SIPp o desde el host (Windows con WSL)?**
   - VM separada: más limpio metodológicamente (separación clara cliente/servidor).
   - WSL en host: más simple de levantar, pero discutible si "carga el resultado".
   - **Sugerencia:** VM separada, clonando la actual y reemplazando los configs.

2. **¿Cuántos endpoints SIP creamos en `pjsip.conf`?**
   - SIPp puede usar el mismo endpoint para N llamadas usando autenticación digest.
   - Más limpio para reportes: crear 200-500 endpoints con un script generador.

3. **¿Audio o silencio durante las llamadas?**
   - Silencio: más simple, RTP solo de keep-alive.
   - Audio: más realista, generamos un `.pcap` con un tono de 1 segundo en loop.

4. **¿Métricas en vivo o post-procesadas?**
   - En vivo: dashboard tipo `htop` + `asterisk -rx "core show channels count"` cada segundo.
   - Post-procesadas: dump a CSV durante el test, analizar con script al final.
   - **Sugerencia:** ambas — dashboard para la demo, CSV para el reporte.

## 8. Referencias técnicas

- **SIPp:** https://sipp.readthedocs.io
- **E-model (cálculo de MOS):** ITU-T G.107
- **Wireshark RTP analysis:** https://wiki.wireshark.org/RTP_statistics
- **Asterisk performance tuning:** https://docs.asterisk.org/Deployment/Performance-Tuning

## 9. Estructura propuesta del nuevo proyecto

```
so-stress-test-asterisk/
├── README.md                 # documentación del nuevo proyecto
├── scenarios/
│   ├── caller_to_100.xml     # SIPp: simular llamada a la AGI
│   ├── caller_to_600.xml     # SIPp: simular llamada a echo
│   └── audio_sample.pcap     # audio que SIPp reproduce
├── tools/
│   ├── generar_endpoints.py  # genera pjsip.conf con N endpoints
│   ├── medir.sh              # captura CPU/RAM/calls cada N seg
│   ├── analizar_pcap.py      # extrae jitter/loss/MOS del pcap
│   └── graficar.py           # CSV → matplotlib PNG
├── results/
│   ├── test_10cc.csv
│   ├── test_50cc.csv
│   ├── ...
│   └── grafica_curva.png
└── reporte_final.pdf         # entrega para el profe
```

## 10. Cómo retomar este proyecto en otro momento

Cuando quieras (o cuando otra persona del equipo) arrancar este proyecto:

1. **Clonar este mismo repo** (ya tiene Asterisk + AGI funcionando, base del experimento)
2. **Crear una rama nueva**: `git checkout -b feature/stress-tests`
3. **Crear la carpeta** `stress-tests/` con la estructura de la sección 9
4. **Instalar SIPp en una VM nueva** (clonar la actual o crear otra Debian)
5. **Empezar por un escenario simple**: 10 llamadas a la extensión 600 durante 1 min, validar que SIPp llega a Asterisk
6. **Ir escalando** cantidad de llamadas hasta encontrar el punto de degradación

## 11. Cuando se entregue, reutilizar la estructura del README actual

El README de este proyecto AGI Taxi (`README.md`) sigue una estructura que funcionó para el profe: **enunciado → cumplimiento punto por punto → arquitectura → flujo → tecnologías → setup → datos → decisiones**. Mantener esa misma estructura en el README del stress test ayuda a que la lectura sea consistente.

---

## Anexo — Cheatsheet inicial de SIPp

```bash
# Instalar SIPp en Debian/Ubuntu (en la VM generadora)
sudo apt install -y sip-tester

# Test minimo: 10 llamadas en serie a la extension 600 (echo)
sipp -sn uac 192.168.56.10 -d 30000 -s 600 -m 10

# Lo mismo pero con concurrencia: 10 llamadas concurrentes durante 60 seg
sipp -sn uac 192.168.56.10 -d 60000 -s 600 -m 10 -l 10

# Con autenticacion (cuando tengamos endpoints con auth en pjsip)
sipp -sn uac 192.168.56.10 -s 600 -ap "TaxiPass1001!" -au 1001 -m 100 -l 50

# Con escenario XML personalizado
sipp -sf scenarios/caller_to_100.xml 192.168.56.10 -m 100 -l 50
```

Banderas clave:
- `-d N`: duración de cada llamada en milisegundos
- `-m N`: total de llamadas a generar
- `-l N`: límite de llamadas concurrentes
- `-r N`: ratio de llamadas por segundo
- `-trace_msg`: log de mensajes SIP (debug)
- `-trace_stat`: dump de estadísticas a CSV
