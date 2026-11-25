// pluglight: керує світлодіодом MagSafe 3 через SMC (ключ ACLC) і показує ним стан AI-агентів.
// Запис у SMC потребує root, тому світлодіодом керує демон (`daemon`), а хуки агентів (`hook`)
// лише записують стан своєї сесії у файл у спільній теці.
#ifdef __APPLE__
#include <IOKit/IOKitLib.h>
#else
#include <stdint.h>
typedef uint16_t UInt16;
typedef uint32_t UInt32;
#endif
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

/* ---------- SMC ---------- */

typedef struct { char major, minor, build, reserved; UInt16 release; } vers_t;
typedef struct { UInt16 version, length; UInt32 cpu, gpu, mem; } plimit_t;
typedef struct { UInt32 dataSize, dataType; char dataAttributes; } keyinfo_t;
typedef struct {
    UInt32 key; vers_t vers; plimit_t plimit; keyinfo_t keyInfo;
    char result, status, data8; UInt32 data32; unsigned char bytes[32];
} SMCKeyData;

enum { KERNEL_INDEX_SMC = 2, CMD_READ = 5, CMD_WRITE = 6, CMD_KEYINFO = 9 };
enum { LED_SYSTEM = 0, LED_OFF = 1, LED_GREEN = 3, LED_ORANGE = 4 };
static const UInt32 KEY_ACLC = ('A' << 24) | ('C' << 16) | ('L' << 8) | 'C';

#ifdef __APPLE__
static io_connect_t conn;

static int smc_open(void) {
    if (conn) return 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    IOObjectRelease(svc);
    return kr == kIOReturnSuccess ? 0 : -1;
}

static int smc_call(SMCKeyData *in, SMCKeyData *out) {
    size_t sz = sizeof(SMCKeyData);
    kern_return_t kr = IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, in, sizeof(*in), out, &sz);
    return kr == kIOReturnSuccess && !out->result ? 0 : -1;
}
#else
static int smc_open(void) { return -1; }
static int smc_call(SMCKeyData *in, SMCKeyData *out) { (void)in; (void)out; return -1; }
#endif

static int smc_keyinfo_of(UInt32 key, keyinfo_t *ki) {
    SMCKeyData in = {0}, out = {0};
    in.key = key; in.data8 = CMD_KEYINFO;
    if (smc_open() || smc_call(&in, &out)) return -1;
    *ki = out.keyInfo;
    return 0;
}

static int smc_keyinfo(keyinfo_t *ki) { return smc_keyinfo_of(KEY_ACLC, ki); }

// Чи є на цьому маку світлодіод MagSafe 3: ключ ACLC існує і займає один байт.
// PLUGLIGHT_PROBE_KEY підставляє інший ключ, щоб перевірити поведінку на маку без MagSafe.
static int led_present(void) {
    UInt32 key = KEY_ACLC;
    const char *k = getenv("PLUGLIGHT_PROBE_KEY");
    if (k && strlen(k) == 4) key = ((UInt32)k[0] << 24) | ((UInt32)k[1] << 16) | ((UInt32)k[2] << 8) | (UInt32)k[3];
    keyinfo_t ki;
    return smc_keyinfo_of(key, &ki) == 0 && ki.dataSize == 1;
}

static int led_read(void) {
    keyinfo_t ki;
    if (smc_keyinfo(&ki)) return -1;
    SMCKeyData in = {0}, out = {0};
    in.key = KEY_ACLC; in.keyInfo.dataSize = ki.dataSize; in.data8 = CMD_READ;
    return smc_call(&in, &out) ? -1 : out.bytes[0];
}

static int led_write(int v) {
    keyinfo_t ki;
    if (smc_keyinfo(&ki) || ki.dataSize != 1) return -1;
    SMCKeyData in = {0}, out = {0};
    in.key = KEY_ACLC; in.keyInfo.dataSize = 1; in.data8 = CMD_WRITE; in.bytes[0] = (unsigned char)v;
    return smc_call(&in, &out);
}

/* ---------- стани сесій ---------- */

// Порядок задає пріоритет: показується найважливіший стан серед усіх сесій.
enum state { ST_IDLE, ST_DONE, ST_BUSY, ST_WAITING, ST_ERROR, ST_COUNT };
static const char *state_names[ST_COUNT] = { "idle", "done", "busy", "waiting", "error" };
// Скільки секунд стан живе без оновлень: агент міг упасти й не надіслати кінець сесії.
static const int state_ttl[ST_COUNT] = { 0, 10 * 60, 20 * 60, 60 * 60, 10 * 60 };

enum pattern { P_SYSTEM, P_GREEN, P_ORANGE, P_ORANGE_SLOW, P_ORANGE_FAST };
static const char *pattern_names[] = {
    "macOS", "green", "orange", "orange, slow blink", "orange, fast blink"
};
// Те саме для файлу стану, який читає програма в рядку меню.
static const char *pattern_ids[] = { "system", "green", "orange", "orange-slow", "orange-fast" };
static const enum pattern state_pattern[ST_COUNT] = { P_SYSTEM, P_GREEN, P_ORANGE, P_ORANGE_SLOW, P_ORANGE_FAST };

static int led_at(enum pattern p, long ms) {
    switch (p) {
    case P_GREEN:       return LED_GREEN;
    case P_ORANGE:      return LED_ORANGE;
    case P_ORANGE_SLOW: return (ms / 700) % 2 ? LED_OFF : LED_ORANGE;
    case P_ORANGE_FAST: return (ms / 150) % 2 ? LED_OFF : LED_ORANGE;
    default:            return LED_SYSTEM;
    }
}

static const char *state_dir(void) {
    const char *d = getenv("PLUGLIGHT_DIR");
    return d && *d ? d : "/tmp/pluglight";
}

static void ensure_dir(void) {
    if (mkdir(state_dir(), 0777) == 0) chmod(state_dir(), 01777);
}

static int parse_state(const char *s) {
    if (!strcmp(s, "notification")) return ST_WAITING;
    for (int i = 0; i < ST_COUNT; i++)
        if (!strcmp(s, state_names[i])) return i;
    return -1;
}

static long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000L + ts.tv_nsec / 1000000;
}

// Читає всі сесії, прибирає прострочені й повертає найважливіший стан.
static enum state scan_sessions(int verbose) {
    enum state top = ST_IDLE;
    DIR *d = opendir(state_dir());
    if (!d) return top;
    time_t now = time(NULL);
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char path[1024], buf[16] = {0};
        snprintf(path, sizeof path, "%s/%s", state_dir(), e->d_name);
        int fd = open(path, O_RDONLY | O_NOFOLLOW);
        if (fd < 0) continue;
        struct stat st;
        ssize_t n = fstat(fd, &st) == 0 && S_ISREG(st.st_mode) ? read(fd, buf, sizeof buf - 1) : -1;
        close(fd);
        if (n <= 0) continue;
        buf[strcspn(buf, "\r\n")] = 0;
        int s = parse_state(buf);
        if (s <= ST_IDLE) continue;
        long age = (long)(now - st.st_mtime);
        if (age > state_ttl[s]) {
            if (verbose) printf("  %-40s %-8s %lds ago (expired)\n", e->d_name, buf, age);
            unlink(path);
            continue;
        }
        if (verbose) printf("  %-40s %-8s %lds ago\n", e->d_name, buf, age);
        if ((enum state)s > top) top = s;
    }
    closedir(d);
    return top;
}

// Ідентифікатор сесії з JSON події агента. Claude Code, Codex, Qwen, Crush, Droid, Kiro і Goose
// шлють "session_id", OpenCode і Kilo Code — "sessionId", Cursor, Gemini і Auggie —
// "conversation_id"/"conversationId", Antigravity і Windsurf — "trajectory_id", Cline — "taskId".
static const char *sid_keys[] = {
    "\"session_id\"", "\"sessionId\"", "\"conversation_id\"", "\"conversationId\"", "\"trajectory_id\"", "\"taskId\"",
};
static void session_from_json(const char *json, char *out, size_t outsz) {
    out[0] = 0;
    for (size_t k = 0; k < sizeof sid_keys / sizeof *sid_keys && !out[0]; k++) {
        const char *p = strstr(json, sid_keys[k]);
        if (!p) continue;
        p += strlen(sid_keys[k]);
        while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' || *p == ':') p++;
        if (*p++ != '"') continue;
        size_t i = 0;
        while (*p && *p != '"' && i + 1 < outsz) out[i++] = *p++;
        out[i] = 0;
    }
}

// Рядкове значення ключа, якщо воно є в JSON: "key": "value".
static int json_string_is(const char *json, const char *key, const char *const *values) {
    const char *p = strstr(json, key);
    if (!p) return 0;
    p += strlen(key);
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' || *p == ':') p++;
    if (*p++ != '"') return 0;
    size_t n = strcspn(p, "\"");
    for (; *values; values++)
        if (strlen(*values) == n && !strncmp(p, *values, n)) return 1;
    return 0;
}

static int json_bool_is_false(const char *json, const char *key) {
    const char *p = strstr(json, key);
    if (!p) return 0;
    p += strlen(key);
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' || *p == ':') p++;
    return strncmp(p, "false", 5) == 0;
}

// Псевдостан "stop": кінець ходу з причиною. Cursor шле "status", Antigravity — "terminationReason",
// Auggie — "agent_stop_cause".
static int stop_state(const char *json) {
    static const char *const aborted[] = { "aborted", "interrupted", NULL };
    static const char *const failed[] = { "error", "max_steps_exceeded", "empty_completion", NULL };
    if (json_string_is(json, "\"status\"", aborted) ||
        json_string_is(json, "\"terminationReason\"", aborted) ||
        json_string_is(json, "\"agent_stop_cause\"", aborted))
        return ST_IDLE;
    if (json_string_is(json, "\"status\"", failed) ||
        json_string_is(json, "\"terminationReason\"", failed) ||
        json_string_is(json, "\"agent_stop_cause\"", failed))
        return ST_ERROR;
    // Antigravity: хід завершився, але фонові задачі ще йдуть.
    return json_bool_is_false(json, "\"fullyIdle\"") ? ST_BUSY : ST_DONE;
}

// Лишає в імені сесії тільки безпечні для файлу символи.
static void sanitize(char *s) {
    char *w = s;
    for (char *r = s; *r && w - s < 64; r++)
        if ((*r >= 'a' && *r <= 'z') || (*r >= 'A' && *r <= 'Z') || (*r >= '0' && *r <= '9') || *r == '-' || *r == '_')
            *w++ = *r;
    *w = 0;
    if (!*s) strcpy(s, "default");
}

static int set_session(const char *session, int s) {
    char sid[128], path[1024], tmp[1100];
    snprintf(sid, sizeof sid, "%s", session);
    sanitize(sid);
    ensure_dir();
    snprintf(path, sizeof path, "%s/%s", state_dir(), sid);
    if (s == ST_IDLE) return unlink(path) == 0 || errno == ENOENT ? 0 : -1;
    snprintf(tmp, sizeof tmp, "%s/.%s.%d", state_dir(), sid, getpid());
    FILE *f = fopen(tmp, "w");
    if (!f) return -1;
    fprintf(f, "%s\n", state_names[s]);
    fclose(f);
    return rename(tmp, path);
}

/* ---------- команди ---------- */

static volatile sig_atomic_t stop_requested;
static void on_signal(int sig) { (void)sig; stop_requested = 1; }

// Пульс програми в рядку меню: вона оновлює цей файл раз на секунду, поки працює й увімкнена.
static int app_alive(void) {
    char path[1024];
    struct stat st;
    snprintf(path, sizeof path, "%s/.app", state_dir());
    return stat(path, &st) == 0 && time(NULL) - st.st_mtime <= 5;
}

// Що зараз показує світлодіод. Пише лише root, у /var/run, куди інші користувачі писати не можуть.
static const char *led_state_path = "/var/run/pluglight.state";

static void write_led_state(enum pattern p) {
    char tmp[256];
    snprintf(tmp, sizeof tmp, "%s.%d", led_state_path, getpid());
    int fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0644);
    if (fd < 0) return;
    dprintf(fd, "%s\n", pattern_ids[p]);
    close(fd);
    if (rename(tmp, led_state_path)) unlink(tmp);
}

static int cmd_daemon(int dry_run, int require_app) {
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    if (!dry_run) {
        if (smc_open() || !led_present()) {
            // Без MagSafe 3 перезапуски нічого не дадуть: пишемо раз і чекаємо зупинки,
            // інакше launchd запускав би демон знову кожні 10 секунд.
            fprintf(stderr, "no MagSafe LED on this Mac (SMC key ACLC not found)\n");
            while (!stop_requested) pause();
            return 0;
        }
        if (led_write(LED_SYSTEM)) {
            fprintf(stderr, "cannot write to the SMC%s\n", geteuid() ? ": run as root" : "");
            return 1;
        }
        write_led_state(P_SYSTEM);
    }
    ensure_dir();
    chmod(state_dir(), 01777);

    enum pattern pat = P_SYSTEM;
    int last = LED_SYSTEM;
    long last_scan = -1000000, last_write = 0;
    while (!stop_requested) {
        long ms = now_ms();
        if (ms - last_scan >= 500) {
            enum pattern p = require_app && !app_alive() ? P_SYSTEM : state_pattern[scan_sessions(0)];
            if (p != pat) {
                pat = p;
                // Кожну зміну в лог не пишемо, щоб він не ріс; dry-run друкує для перевірки.
                if (dry_run) { printf("%s\n", pattern_names[pat]); fflush(stdout); }
                else write_led_state(pat);
            }
            last_scan = ms;
        }
        int v = led_at(pat, ms);
        // macOS може сама перемкнути світлодіод (наприклад, коли змінюється зарядка),
        // тому свій колір час від часу записуємо знову; системний режим — лише раз.
        if (v != last || (v != LED_SYSTEM && ms - last_write >= 5000)) {
            if (!dry_run) led_write(v);
            last = v;
            last_write = ms;
        }
        usleep(50000);
    }
    if (!dry_run) { led_write(LED_SYSTEM); write_led_state(P_SYSTEM); }
    return 0;
}

// Чи вже закрився JSON-об'єкт верхнього рівня (з урахуванням рядків і екранування).
static int json_complete(const char *s, size_t n) {
    int depth = 0, in_str = 0, esc = 0, seen = 0;
    for (size_t i = 0; i < n; i++) {
        char c = s[i];
        if (in_str) {
            if (esc) esc = 0;
            else if (c == '\\') esc = 1;
            else if (c == '"') in_str = 0;
        } else if (c == '"') in_str = 1;
        else if (c == '{' || c == '[') { depth++; seen = 1; }
        else if (c == '}' || c == ']') { if (--depth == 0 && seen) return 1; }
    }
    return 0;
}

// Читає JSON події зі stdin. Деякі агенти (Antigravity) не закривають stdin одразу, тож не
// чекаємо EOF: зупиняємось, щойно об'єкт закрився, або після короткої паузи без даних.
static size_t read_event(char *buf, size_t cap) {
    size_t n = 0;
    if (isatty(STDIN_FILENO)) return 0;
    int wait_ms = 2000;
    while (n < cap - 1) {
        struct pollfd p = { STDIN_FILENO, POLLIN, 0 };
        int pr = poll(&p, 1, wait_ms);
        if (pr <= 0) break;
        ssize_t r = read(STDIN_FILENO, buf + n, cap - 1 - n);
        if (r <= 0) break;
        n += (size_t)r;
        if (json_complete(buf, n)) break;
        wait_ms = 300;
    }
    return n;
}

// Слід останнього виклику хука для кожного агента: `pluglight status` показує, чи хуки взагалі
// спрацьовують. Крапка на початку — сканер сесій такі файли пропускає.
static void trace_hook(const char *agent, const char *state_name, const char *sid) {
    char a[64], path[1024], tmp[1100];
    snprintf(a, sizeof a, "%s", agent && *agent ? agent : "unknown");
    sanitize(a);
    ensure_dir();
    snprintf(path, sizeof path, "%s/.hook-%s", state_dir(), a);
    snprintf(tmp, sizeof tmp, "%s/.hook-%s.%d", state_dir(), a, getpid());
    FILE *f = fopen(tmp, "w");
    if (!f) return;
    fprintf(f, "%s %s\n", state_name, *sid ? sid : "(no-session-id)");
    fclose(f);
    rename(tmp, path);
}

static int cmd_hook(const char *state_name, const char *agent) {
    // Хук ніколи не має заважати агентові: жодного виводу і завжди код 0.
    static char buf[65536];
    size_t n = read_event(buf, sizeof buf);
    buf[n] = 0;
    int s = !strcmp(state_name, "stop") ? stop_state(buf) : parse_state(state_name);
    char sid[128];
    session_from_json(buf, sid, sizeof sid);
    trace_hook(agent, state_name, sid);
    if (s < 0) return 0;
    // OpenCode з oh-my-openagent запускає хуки Claude Code зі своїм session_id (ses_...) і без Stop:
    // така сесія висіла б у «працює» 20 хвилин. Її веде плагін OpenCode, тож тут пропускаємо.
    if (agent && !strcmp(agent, "claude") && !strncmp(sid, "ses_", 4)) return 0;
    set_session(sid, s);
    return 0;
}

static int cmd_status(void) {
    printf("Sessions (%s):\n", state_dir());
    enum state top = scan_sessions(1);
    printf("LED: %s\n", pattern_names[state_pattern[top]]);
    DIR *d = opendir(state_dir());
    if (!d) return 0;
    int header = 0;
    time_t now = time(NULL);
    struct dirent *e;
    while ((e = readdir(d))) {
        if (strncmp(e->d_name, ".hook-", 6) || strchr(e->d_name + 6, '.')) continue;
        char path[1024], buf[200] = {0};
        snprintf(path, sizeof path, "%s/%s", state_dir(), e->d_name);
        struct stat st;
        FILE *f = fopen(path, "r");
        if (!f) continue;
        if (!fgets(buf, sizeof buf, f)) buf[0] = 0;
        fclose(f);
        if (stat(path, &st)) continue;
        buf[strcspn(buf, "\r\n")] = 0;
        if (!header) { printf("Last hook calls:\n"); header = 1; }
        printf("  %-12s %-40s %lds ago\n", e->d_name + 6, buf, (long)(now - st.st_mtime));
    }
    closedir(d);
    return 0;
}

static int cmd_probe(void) {
    int ok = smc_open() == 0 && led_present();
    printf(ok ? "MagSafe LED: found\n" : "MagSafe LED: not found (this Mac has no MagSafe 3)\n");
    return ok ? 0 : 1;
}

static int cmd_clear(void) {
    DIR *d = opendir(state_dir());
    if (!d) return 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char path[1024];
        snprintf(path, sizeof path, "%s/%s", state_dir(), e->d_name);
        unlink(path);
    }
    closedir(d);
    return 0;
}

static int cmd_led(int argc, char **argv) {
    if (argc == 0) {
        int v = led_read();
        if (v < 0) { fprintf(stderr, "cannot read the SMC key ACLC\n"); return 1; }
        printf("ACLC = 0x%02x\n", v);
        return 0;
    }
    char *end;
    long v = strtol(argv[0], &end, 0);
    if (*end || v < 0 || v > 7) { fprintf(stderr, "value must be 0 to 7\n"); return 1; }
    if (led_write((int)v)) {
        fprintf(stderr, "cannot write to the SMC%s\n", geteuid() ? ": run with sudo" : "");
        return 1;
    }
    return 0;
}

static int blink_restore;
static void blink_signal(int sig) { (void)sig; if (blink_restore) led_write(LED_SYSTEM); _exit(1); }

static int cmd_blink(int n) {
    signal(SIGINT, blink_signal);
    signal(SIGTERM, blink_signal);
    static const int seq[] = { LED_GREEN, LED_ORANGE, LED_OFF };
    for (int i = 0; i < n; i++)
        for (int j = 0; j < 3; j++) {
            if (led_write(seq[j])) {
                fprintf(stderr, "cannot write to the SMC%s\n", geteuid() ? ": run with sudo" : "");
                return 1;
            }
            blink_restore = 1;
            usleep(600000);
        }
    led_write(LED_SYSTEM);
    return 0;
}

static void usage(void) {
    fputs(
        "pluglight: the MagSafe LED as a status light for AI agents\n"
        "\n"
        "  pluglight status                 sessions and what the LED shows\n"
        "  pluglight set <state> [session]  set a state by hand (default session: manual)\n"
        "  pluglight hook <state> [agent]   for agent hooks: the session comes from JSON on stdin;\n"
        "                                       state may be \"stop\" (the reason comes from the event)\n"
        "  pluglight clear                  remove all sessions\n"
        "  pluglight probe                  check that this Mac has the MagSafe LED\n"
        "  pluglight daemon [--dry-run] [--require-app]\n"
        "                                       drive the LED (root; run by the LaunchDaemon);\n"
        "                                       --require-app: only while PlugLight.app is running\n"
        "  pluglight led [0-7]              read or write ACLC directly (writing needs sudo)\n"
        "  pluglight blink [n]              test: green, orange, off (sudo)\n"
        "\n"
        "States: busy, waiting, done, error, idle (idle removes the session), notification = waiting.\n"
        "Priority: error > waiting > busy > done.\n", stderr);
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(); return 1; }
    const char *cmd = argv[1];
    if (!strcmp(cmd, "hook")) return argc > 2 ? cmd_hook(argv[2], argc > 3 ? argv[3] : NULL) : 0;
    if (!strcmp(cmd, "status")) return cmd_status();
    if (!strcmp(cmd, "clear")) return cmd_clear();
    if (!strcmp(cmd, "probe")) return cmd_probe();
    if (!strcmp(cmd, "daemon")) {
        int dry_run = 0, require_app = 0;
        for (int i = 2; i < argc; i++) {
            if (!strcmp(argv[i], "--dry-run")) dry_run = 1;
            else if (!strcmp(argv[i], "--require-app")) require_app = 1;
        }
        return cmd_daemon(dry_run, require_app);
    }
    if (!strcmp(cmd, "led")) return cmd_led(argc - 2, argv + 2);
    if (!strcmp(cmd, "blink")) return cmd_blink(argc > 2 ? atoi(argv[2]) : 3);
    if (!strcmp(cmd, "set") && argc > 2) {
        int s = parse_state(argv[2]);
        if (s < 0) { fprintf(stderr, "unknown state: %s\n", argv[2]); return 1; }
        if (set_session(argc > 3 ? argv[3] : "manual", s)) { perror("set"); return 1; }
        return 0;
    }
    usage();
    return 1;
}
