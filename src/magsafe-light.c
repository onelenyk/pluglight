// magsafe-light: керує світлодіодом MagSafe 3 через SMC (ключ ACLC) і показує ним стан AI-агентів.
// Запис у SMC потребує root, тому світлодіодом керує демон (`daemon`), а хуки агентів (`hook`)
// лише записують стан своєї сесії у файл у спільній теці.
#include <IOKit/IOKitLib.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
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

static int smc_keyinfo(keyinfo_t *ki) {
    SMCKeyData in = {0}, out = {0};
    in.key = KEY_ACLC; in.data8 = CMD_KEYINFO;
    if (smc_open() || smc_call(&in, &out)) return -1;
    *ki = out.keyInfo;
    return 0;
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
    "керує macOS", "зелений", "помаранчевий", "помаранчевий, повільно блимає", "помаранчевий, швидко блимає"
};
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
    const char *d = getenv("MAGSAFE_LIGHT_DIR");
    return d && *d ? d : "/tmp/magsafe-light";
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
            if (verbose) printf("  %-40s %-8s %lds тому (прострочено)\n", e->d_name, buf, age);
            unlink(path);
            continue;
        }
        if (verbose) printf("  %-40s %-8s %lds тому\n", e->d_name, buf, age);
        if ((enum state)s > top) top = s;
    }
    closedir(d);
    return top;
}

// Ідентифікатор сесії з JSON події агента: значення поля "session_id" (або "sessionId").
static void session_from_json(const char *json, char *out, size_t outsz) {
    static const char *keys[] = { "\"session_id\"", "\"sessionId\"" };
    out[0] = 0;
    for (int k = 0; k < 2 && !out[0]; k++) {
        const char *p = strstr(json, keys[k]);
        if (!p) continue;
        p += strlen(keys[k]);
        while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' || *p == ':') p++;
        if (*p++ != '"') continue;
        size_t i = 0;
        while (*p && *p != '"' && i + 1 < outsz) out[i++] = *p++;
        out[i] = 0;
    }
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

static int cmd_daemon(int dry_run) {
    if (!dry_run) {
        if (smc_open() || led_write(LED_SYSTEM)) {
            fprintf(stderr, "не вдалося записати в SMC%s\n", geteuid() ? ": потрібен root" : "");
            return 1;
        }
    }
    ensure_dir();
    chmod(state_dir(), 01777);
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    enum pattern pat = P_SYSTEM;
    int last = LED_SYSTEM;
    long last_scan = -1000000, last_write = 0;
    while (!stop_requested) {
        long ms = now_ms();
        if (ms - last_scan >= 500) {
            enum pattern p = state_pattern[scan_sessions(0)];
            if (p != pat) {
                pat = p;
                printf("%s\n", pattern_names[pat]);
                fflush(stdout);
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
    if (!dry_run) led_write(LED_SYSTEM);
    return 0;
}

static int cmd_hook(const char *state_name) {
    // Хук ніколи не має заважати агентові: жодного виводу і завжди код 0.
    int s = parse_state(state_name);
    if (s < 0) return 0;
    static char buf[65536];
    size_t n = 0;
    if (!isatty(STDIN_FILENO)) {
        ssize_t r;
        while (n < sizeof buf - 1 && (r = read(STDIN_FILENO, buf + n, sizeof buf - 1 - n)) > 0) n += r;
    }
    buf[n] = 0;
    char sid[128];
    session_from_json(buf, sid, sizeof sid);
    set_session(sid, s);
    return 0;
}

static int cmd_status(void) {
    printf("Сесії (%s):\n", state_dir());
    enum state top = scan_sessions(1);
    printf("Світлодіод: %s\n", pattern_names[state_pattern[top]]);
    return 0;
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
        if (v < 0) { fprintf(stderr, "не вдалося прочитати ключ ACLC\n"); return 1; }
        printf("ACLC = 0x%02x\n", v);
        return 0;
    }
    char *end;
    long v = strtol(argv[0], &end, 0);
    if (*end || v < 0 || v > 7) { fprintf(stderr, "значення має бути від 0 до 7\n"); return 1; }
    if (led_write((int)v)) {
        fprintf(stderr, "не вдалося записати в SMC%s\n", geteuid() ? ": потрібен sudo" : "");
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
                fprintf(stderr, "не вдалося записати в SMC%s\n", geteuid() ? ": потрібен sudo" : "");
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
        "magsafe-light — світлодіод MagSafe як індикатор AI-агента\n"
        "\n"
        "  magsafe-light status                 сесії і що зараз показує світлодіод\n"
        "  magsafe-light set <стан> [сесія]     вручну задати стан (за замовчуванням сесія manual)\n"
        "  magsafe-light hook <стан>            для хуків агента: сесія береться з JSON на stdin\n"
        "  magsafe-light clear                  прибрати всі сесії\n"
        "  magsafe-light daemon [--dry-run]     керувати світлодіодом (root; запускає LaunchDaemon)\n"
        "  magsafe-light led [0-7]              прочитати або записати ACLC напряму (запис — sudo)\n"
        "  magsafe-light blink [n]              тест: зелений, помаранчевий, вимкнений (sudo)\n"
        "\n"
        "Стани: busy, waiting, done, error, idle (idle прибирає сесію), notification = waiting.\n"
        "Пріоритет: error > waiting > busy > done.\n", stderr);
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(); return 1; }
    const char *cmd = argv[1];
    if (!strcmp(cmd, "hook")) return argc > 2 ? cmd_hook(argv[2]) : 0;
    if (!strcmp(cmd, "status")) return cmd_status();
    if (!strcmp(cmd, "clear")) return cmd_clear();
    if (!strcmp(cmd, "daemon")) return cmd_daemon(argc > 2 && !strcmp(argv[2], "--dry-run"));
    if (!strcmp(cmd, "led")) return cmd_led(argc - 2, argv + 2);
    if (!strcmp(cmd, "blink")) return cmd_blink(argc > 2 ? atoi(argv[2]) : 3);
    if (!strcmp(cmd, "set") && argc > 2) {
        int s = parse_state(argv[2]);
        if (s < 0) { fprintf(stderr, "невідомий стан: %s\n", argv[2]); return 1; }
        if (set_session(argc > 3 ? argv[3] : "manual", s)) { perror("set"); return 1; }
        return 0;
    }
    usage();
    return 1;
}
