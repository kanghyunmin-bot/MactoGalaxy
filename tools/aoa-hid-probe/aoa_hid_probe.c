#include <libusb-1.0/libusb.h>

#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define AOA_GET_PROTOCOL 51
#define AOA_SEND_STRING 52
#define AOA_START 53
#define AOA_REGISTER_HID 54
#define AOA_UNREGISTER_HID 55
#define AOA_SET_HID_REPORT_DESC 56
#define AOA_SEND_HID_EVENT 57

#define USB_DIR_OUT 0x00
#define USB_DIR_IN 0x80
#define USB_TYPE_VENDOR 0x40
#define USB_RECIP_DEVICE 0x00
#define USB_TIMEOUT_MS 1000

#define GOOGLE_VENDOR_ID 0x18d1

#define HID_ID_KEYBOARD 1
#define HID_ID_MOUSE 2
#define HID_ID_TOUCH 3

static volatile sig_atomic_t interrupted = 0;

static const uint8_t keyboard_report_descriptor[] = {
    0x05, 0x01,       // Usage Page (Generic Desktop)
    0x09, 0x06,       // Usage (Keyboard)
    0xa1, 0x01,       // Collection (Application)
    0x05, 0x07,       // Usage Page (Keyboard)
    0x19, 0xe0,       // Usage Minimum (Keyboard LeftControl)
    0x29, 0xe7,       // Usage Maximum (Keyboard Right GUI)
    0x15, 0x00,       // Logical Minimum (0)
    0x25, 0x01,       // Logical Maximum (1)
    0x75, 0x01,       // Report Size (1)
    0x95, 0x08,       // Report Count (8)
    0x81, 0x02,       // Input (Data, Variable, Absolute)
    0x95, 0x01,       // Report Count (1)
    0x75, 0x08,       // Report Size (8)
    0x81, 0x01,       // Input (Constant)
    0x95, 0x05,       // Report Count (5)
    0x75, 0x01,       // Report Size (1)
    0x05, 0x08,       // Usage Page (LEDs)
    0x19, 0x01,       // Usage Minimum (Num Lock)
    0x29, 0x05,       // Usage Maximum (Kana)
    0x91, 0x02,       // Output (Data, Variable, Absolute)
    0x95, 0x01,       // Report Count (1)
    0x75, 0x03,       // Report Size (3)
    0x91, 0x01,       // Output (Constant)
    0x95, 0x06,       // Report Count (6)
    0x75, 0x08,       // Report Size (8)
    0x15, 0x00,       // Logical Minimum (0)
    0x26, 0x90, 0x00, // Logical Maximum (144 / Keyboard LANG1)
    0x05, 0x07,       // Usage Page (Keyboard)
    0x19, 0x00,       // Usage Minimum (Reserved)
    0x29, 0x90,       // Usage Maximum (Keyboard LANG1)
    0x81, 0x00,       // Input (Data, Array)
    0xc0              // End Collection
};

static const uint8_t mouse_report_descriptor[] = {
    0x05, 0x01,       // Usage Page (Generic Desktop)
    0x09, 0x02,       // Usage (Mouse)
    0xa1, 0x01,       // Collection (Application)
    0x09, 0x01,       // Usage (Pointer)
    0xa1, 0x00,       // Collection (Physical)
    0x05, 0x09,       // Usage Page (Buttons)
    0x19, 0x01,       // Usage Minimum (Button 1)
    0x29, 0x03,       // Usage Maximum (Button 3)
    0x15, 0x00,       // Logical Minimum (0)
    0x25, 0x01,       // Logical Maximum (1)
    0x95, 0x03,       // Report Count (3)
    0x75, 0x01,       // Report Size (1)
    0x81, 0x02,       // Input (Data, Variable, Absolute)
    0x95, 0x01,       // Report Count (1)
    0x75, 0x05,       // Report Size (5)
    0x81, 0x01,       // Input (Constant)
    0x05, 0x01,       // Usage Page (Generic Desktop)
    0x09, 0x30,       // Usage (X)
    0x09, 0x31,       // Usage (Y)
    0x09, 0x38,       // Usage (Wheel)
    0x15, 0x81,       // Logical Minimum (-127)
    0x25, 0x7f,       // Logical Maximum (127)
    0x75, 0x08,       // Report Size (8)
    0x95, 0x03,       // Report Count (3)
    0x81, 0x06,       // Input (Data, Variable, Relative)
    0xc0,             // End Collection
    0xc0              // End Collection
};

static const uint8_t touch_report_descriptor[] = {
    0x05, 0x0d,       // Usage Page (Digitizers)
    0x09, 0x04,       // Usage (Touch Screen)
    0xa1, 0x01,       // Collection (Application)
    0x09, 0x22,       // Usage (Finger)
    0xa1, 0x02,       // Collection (Logical)
    0x09, 0x42,       // Usage (Tip Switch)
    0x09, 0x32,       // Usage (In Range)
    0x15, 0x00,       // Logical Minimum (0)
    0x25, 0x01,       // Logical Maximum (1)
    0x75, 0x01,       // Report Size (1)
    0x95, 0x02,       // Report Count (2)
    0x81, 0x02,       // Input (Data, Variable, Absolute)
    0x95, 0x06,       // Report Count (6)
    0x81, 0x03,       // Input (Constant, Variable)
    0x09, 0x51,       // Usage (Contact Identifier)
    0x75, 0x08,       // Report Size (8)
    0x95, 0x01,       // Report Count (1)
    0x15, 0x00,       // Logical Minimum (0)
    0x25, 0x7f,       // Logical Maximum (127)
    0x81, 0x02,       // Input (Data, Variable, Absolute)
    0x05, 0x01,       // Usage Page (Generic Desktop)
    0x09, 0x30,       // Usage (X)
    0x09, 0x31,       // Usage (Y)
    0x16, 0x00, 0x00, // Logical Minimum (0)
    0x26, 0xff, 0x7f, // Logical Maximum (32767)
    0x75, 0x10,       // Report Size (16)
    0x95, 0x02,       // Report Count (2)
    0x81, 0x02,       // Input (Data, Variable, Absolute)
    0xc0,             // End Collection
    0x09, 0x22,       // Usage (Finger)
    0xa1, 0x02,       // Collection (Logical)
    0x05, 0x0d,       // Usage Page (Digitizers)
    0x09, 0x42,       // Usage (Tip Switch)
    0x09, 0x32,       // Usage (In Range)
    0x15, 0x00,       // Logical Minimum (0)
    0x25, 0x01,       // Logical Maximum (1)
    0x75, 0x01,       // Report Size (1)
    0x95, 0x02,       // Report Count (2)
    0x81, 0x02,       // Input (Data, Variable, Absolute)
    0x95, 0x06,       // Report Count (6)
    0x81, 0x03,       // Input (Constant, Variable)
    0x09, 0x51,       // Usage (Contact Identifier)
    0x75, 0x08,       // Report Size (8)
    0x95, 0x01,       // Report Count (1)
    0x15, 0x00,       // Logical Minimum (0)
    0x25, 0x7f,       // Logical Maximum (127)
    0x81, 0x02,       // Input (Data, Variable, Absolute)
    0x05, 0x01,       // Usage Page (Generic Desktop)
    0x09, 0x30,       // Usage (X)
    0x09, 0x31,       // Usage (Y)
    0x16, 0x00, 0x00, // Logical Minimum (0)
    0x26, 0xff, 0x7f, // Logical Maximum (32767)
    0x75, 0x10,       // Report Size (16)
    0x95, 0x02,       // Report Count (2)
    0x81, 0x02,       // Input (Data, Variable, Absolute)
    0xc0,             // End Collection
    0x05, 0x0d,       // Usage Page (Digitizers)
    0x09, 0x54,       // Usage (Contact Count)
    0x15, 0x00,       // Logical Minimum (0)
    0x25, 0x02,       // Logical Maximum (2)
    0x75, 0x08,       // Report Size (8)
    0x95, 0x01,       // Report Count (1)
    0x81, 0x02,       // Input (Data, Variable, Absolute)
    0xc0              // End Collection
};

static void on_signal(int signum) {
    (void)signum;
    interrupted = 1;
}

static const char *usb_error_name(int error_code) {
    return libusb_error_name(error_code);
}

static bool is_aoa_product(uint16_t vendor_id, uint16_t product_id) {
    if (vendor_id != GOOGLE_VENDOR_ID) {
        return false;
    }

    return product_id >= 0x2d00 && product_id <= 0x2d05;
}

static void print_device(libusb_device *device) {
    struct libusb_device_descriptor descriptor;
    int rc = libusb_get_device_descriptor(device, &descriptor);
    if (rc != 0) {
        fprintf(stderr, "failed to read descriptor: %s\n", usb_error_name(rc));
        return;
    }

    printf(
        "bus=%03u address=%03u vid=%04x pid=%04x class=%02x subclass=%02x protocol=%02x",
        libusb_get_bus_number(device),
        libusb_get_device_address(device),
        descriptor.idVendor,
        descriptor.idProduct,
        descriptor.bDeviceClass,
        descriptor.bDeviceSubClass,
        descriptor.bDeviceProtocol
    );

    libusb_device_handle *handle = NULL;
    rc = libusb_open(device, &handle);
    if (rc == 0 && handle != NULL) {
        unsigned char value[256];
        int len = 0;
        if (descriptor.iManufacturer != 0) {
            len = libusb_get_string_descriptor_ascii(handle, descriptor.iManufacturer, value, sizeof(value));
            if (len > 0) {
                printf(" manufacturer=\"%.*s\"", len, value);
            }
        }
        if (descriptor.iProduct != 0) {
            len = libusb_get_string_descriptor_ascii(handle, descriptor.iProduct, value, sizeof(value));
            if (len > 0) {
                printf(" product=\"%.*s\"", len, value);
            }
        }
        if (descriptor.iSerialNumber != 0) {
            len = libusb_get_string_descriptor_ascii(handle, descriptor.iSerialNumber, value, sizeof(value));
            if (len > 0) {
                printf(" serial=\"%.*s\"", len, value);
            }
        }
        libusb_close(handle);
    } else {
        printf(" open_error=%s", usb_error_name(rc));
    }

    if (is_aoa_product(descriptor.idVendor, descriptor.idProduct)) {
        printf(" aoa_mode=true");
    }

    printf("\n");
}

static libusb_device *find_android_candidate(libusb_context *context, bool prefer_aoa) {
    libusb_device **devices = NULL;
    ssize_t count = libusb_get_device_list(context, &devices);
    if (count < 0) {
        fprintf(stderr, "libusb_get_device_list failed: %s\n", usb_error_name((int)count));
        return NULL;
    }

    libusb_device *best = NULL;
    for (ssize_t i = 0; i < count; i++) {
        struct libusb_device_descriptor descriptor;
        if (libusb_get_device_descriptor(devices[i], &descriptor) != 0) {
            continue;
        }

        bool aoa = is_aoa_product(descriptor.idVendor, descriptor.idProduct);
        bool samsung_android = descriptor.idVendor == 0x04e8;
        bool google_android = descriptor.idVendor == GOOGLE_VENDOR_ID;
        bool candidate = aoa || samsung_android || google_android;

        if (!candidate) {
            continue;
        }

        if (prefer_aoa && !aoa) {
            continue;
        }

        best = libusb_ref_device(devices[i]);
        break;
    }

    libusb_free_device_list(devices, 1);
    return best;
}

static int aoa_get_protocol(libusb_device_handle *handle, uint16_t *protocol) {
    uint8_t buffer[2] = {0, 0};
    int rc = libusb_control_transfer(
        handle,
        USB_DIR_IN | USB_TYPE_VENDOR | USB_RECIP_DEVICE,
        AOA_GET_PROTOCOL,
        0,
        0,
        buffer,
        sizeof(buffer),
        USB_TIMEOUT_MS
    );
    if (rc < 0) {
        return rc;
    }
    if (rc != 2) {
        return LIBUSB_ERROR_IO;
    }
    *protocol = (uint16_t)(buffer[0] | (buffer[1] << 8));
    return 0;
}

static int aoa_send_string(libusb_device_handle *handle, uint16_t index, const char *value) {
    return libusb_control_transfer(
        handle,
        USB_DIR_OUT | USB_TYPE_VENDOR | USB_RECIP_DEVICE,
        AOA_SEND_STRING,
        0,
        index,
        (unsigned char *)value,
        (uint16_t)(strlen(value) + 1),
        USB_TIMEOUT_MS
    );
}

static int aoa_start(libusb_device_handle *handle) {
    return libusb_control_transfer(
        handle,
        USB_DIR_OUT | USB_TYPE_VENDOR | USB_RECIP_DEVICE,
        AOA_START,
        0,
        0,
        NULL,
        0,
        USB_TIMEOUT_MS
    );
}

static int aoa_register_hid(libusb_device_handle *handle, uint16_t hid_id, uint16_t descriptor_length) {
    return libusb_control_transfer(
        handle,
        USB_DIR_OUT | USB_TYPE_VENDOR | USB_RECIP_DEVICE,
        AOA_REGISTER_HID,
        hid_id,
        descriptor_length,
        NULL,
        0,
        USB_TIMEOUT_MS
    );
}

static int aoa_set_hid_descriptor(
    libusb_device_handle *handle,
    uint16_t hid_id,
    const uint8_t *descriptor,
    size_t descriptor_length
) {
    size_t offset = 0;
    while (offset < descriptor_length) {
        size_t remaining = descriptor_length - offset;
        uint16_t chunk_length = (uint16_t)(remaining > 64 ? 64 : remaining);
        int rc = libusb_control_transfer(
            handle,
            USB_DIR_OUT | USB_TYPE_VENDOR | USB_RECIP_DEVICE,
            AOA_SET_HID_REPORT_DESC,
            hid_id,
            (uint16_t)offset,
            (unsigned char *)(descriptor + offset),
            chunk_length,
            USB_TIMEOUT_MS
        );
        if (rc < 0) {
            return rc;
        }
        if (rc != chunk_length) {
            return LIBUSB_ERROR_IO;
        }
        offset += chunk_length;
    }
    return 0;
}

static int aoa_send_hid_event(libusb_device_handle *handle, uint16_t hid_id, const uint8_t *report, size_t report_length) {
    int rc = libusb_control_transfer(
        handle,
        USB_DIR_OUT | USB_TYPE_VENDOR | USB_RECIP_DEVICE,
        AOA_SEND_HID_EVENT,
        hid_id,
        0,
        (unsigned char *)report,
        (uint16_t)report_length,
        USB_TIMEOUT_MS
    );
    if (rc < 0) {
        return rc;
    }
    return rc == (int)report_length ? 0 : LIBUSB_ERROR_IO;
}

static int register_hid_device(
    libusb_device_handle *handle,
    uint16_t hid_id,
    const uint8_t *descriptor,
    size_t descriptor_length
) {
    int rc = aoa_register_hid(handle, hid_id, (uint16_t)descriptor_length);
    if (rc < 0) {
        return rc;
    }
    return aoa_set_hid_descriptor(handle, hid_id, descriptor, descriptor_length);
}

static int send_keyboard_a_test(libusb_device_handle *handle) {
    const uint8_t key_down[8] = {0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00};
    const uint8_t key_up[8] = {0};
    int rc = aoa_send_hid_event(handle, HID_ID_KEYBOARD, key_down, sizeof(key_down));
    if (rc < 0) {
        return rc;
    }
    usleep(25000);
    return aoa_send_hid_event(handle, HID_ID_KEYBOARD, key_up, sizeof(key_up));
}

static int send_mouse_test(libusb_device_handle *handle) {
    const uint8_t moves[][4] = {
        {0x00, 40, 0, 0},
        {0x00, 0, 40, 0},
        {0x00, (uint8_t)-40, 0, 0},
        {0x00, 0, (uint8_t)-40, 0},
        {0x01, 0, 0, 0},
        {0x00, 0, 0, 0},
    };

    for (size_t i = 0; i < sizeof(moves) / sizeof(moves[0]); i++) {
        int rc = aoa_send_hid_event(handle, HID_ID_MOUSE, moves[i], sizeof(moves[i]));
        if (rc < 0) {
            return rc;
        }
        usleep(40000);
    }
    return 0;
}

static int send_keyboard_report(libusb_device_handle *handle, uint8_t modifiers, uint8_t usage) {
    uint8_t key_down[8] = {modifiers, 0x00, usage, 0x00, 0x00, 0x00, 0x00, 0x00};
    uint8_t key_up[8] = {0};
    int rc = aoa_send_hid_event(handle, HID_ID_KEYBOARD, key_down, sizeof(key_down));
    if (rc < 0) {
        return rc;
    }
    usleep(10000);
    return aoa_send_hid_event(handle, HID_ID_KEYBOARD, key_up, sizeof(key_up));
}

static int send_mouse_report(libusb_device_handle *handle, uint8_t buttons, int dx, int dy, int wheel) {
    uint8_t report[4] = {
        buttons,
        (uint8_t)(int8_t)(dx < -127 ? -127 : (dx > 127 ? 127 : dx)),
        (uint8_t)(int8_t)(dy < -127 ? -127 : (dy > 127 ? 127 : dy)),
        (uint8_t)(int8_t)(wheel < -127 ? -127 : (wheel > 127 ? 127 : wheel))
    };
    return aoa_send_hid_event(handle, HID_ID_MOUSE, report, sizeof(report));
}

static uint16_t clamp_touch_coordinate(int value) {
    if (value < 0) {
        return 0;
    }
    if (value > 32767) {
        return 32767;
    }
    return (uint16_t)value;
}

static void put_u16_le(uint8_t *target, uint16_t value) {
    target[0] = (uint8_t)(value & 0xff);
    target[1] = (uint8_t)((value >> 8) & 0xff);
}

static int send_touch_report(
    libusb_device_handle *handle,
    bool active,
    int x1,
    int y1,
    int x2,
    int y2
) {
    uint8_t report[13] = {0};
    report[0] = active ? 0x03 : 0x00;
    report[1] = 1;
    put_u16_le(report + 2, clamp_touch_coordinate(x1));
    put_u16_le(report + 4, clamp_touch_coordinate(y1));
    report[6] = active ? 0x03 : 0x00;
    report[7] = 2;
    put_u16_le(report + 8, clamp_touch_coordinate(x2));
    put_u16_le(report + 10, clamp_touch_coordinate(y2));
    report[12] = active ? 2 : 0;
    return aoa_send_hid_event(handle, HID_ID_TOUCH, report, sizeof(report));
}

static int send_pinch_sequence(libusb_device_handle *handle, int center_x, int center_y, int delta, int steps) {
    if (steps < 2) {
        steps = 2;
    }
    if (steps > 24) {
        steps = 24;
    }

    int start_span = delta >= 0 ? 850 : 2600;
    int end_span = delta >= 0 ? 2600 + delta : 850 + delta;
    if (end_span < 320) {
        end_span = 320;
    }
    if (end_span > 7200) {
        end_span = 7200;
    }

    for (int i = 0; i <= steps; i++) {
        double t = (double)i / (double)steps;
        int span = (int)((double)start_span + ((double)(end_span - start_span) * t));
        int rc = send_touch_report(
            handle,
            true,
            center_x - span,
            center_y - span,
            center_x + span,
            center_y + span
        );
        if (rc < 0) {
            return rc;
        }
        usleep(12000);
    }

    int final_span = end_span;
    int rc = send_touch_report(
        handle,
        false,
        center_x - final_span,
        center_y - final_span,
        center_x + final_span,
        center_y + final_span
    );
    usleep(12000);
    return rc;
}

static int parse_int(const char *value, int *out) {
    char *end = NULL;
    errno = 0;
    long parsed = strtol(value, &end, 0);
    if (errno != 0 || end == value || *end != '\0' || parsed < INT32_MIN || parsed > INT32_MAX) {
        return -1;
    }
    *out = (int)parsed;
    return 0;
}

static int run_stdio_loop(libusb_device_handle *handle) {
    char line[256];
    printf("READY\n");
    fflush(stdout);

    while (!interrupted && fgets(line, sizeof(line), stdin) != NULL) {
        char command[32] = {0};
        char a[32] = {0};
        char b[32] = {0};
        char c[32] = {0};
        char d[32] = {0};
        int count = sscanf(line, "%31s %31s %31s %31s %31s", command, a, b, c, d);
        int rc = 0;

        if (count <= 0) {
            continue;
        }
        if (strcmp(command, "quit") == 0) {
            printf("OK quit\n");
            fflush(stdout);
            return 0;
        }
        if (strcmp(command, "mouse") == 0) {
            int buttons = 0;
            int dx = 0;
            int dy = 0;
            int wheel = 0;
            if (count != 5 ||
                parse_int(a, &buttons) != 0 ||
                parse_int(b, &dx) != 0 ||
                parse_int(c, &dy) != 0 ||
                parse_int(d, &wheel) != 0) {
                printf("ERR mouse usage: mouse <buttons> <dx> <dy> <wheel>\n");
                fflush(stdout);
                continue;
            }
            rc = send_mouse_report(handle, (uint8_t)buttons, dx, dy, wheel);
        } else if (strcmp(command, "key") == 0) {
            int modifiers = 0;
            int usage = 0;
            if (count != 3 || parse_int(a, &modifiers) != 0 || parse_int(b, &usage) != 0) {
                printf("ERR key usage: key <modifiers> <hid_usage>\n");
                fflush(stdout);
                continue;
            }
            rc = send_keyboard_report(handle, (uint8_t)modifiers, (uint8_t)usage);
        } else if (strcmp(command, "pinch") == 0) {
            int center_x = 0;
            int center_y = 0;
            int delta = 0;
            int steps = 8;
            if (count < 4 ||
                parse_int(a, &center_x) != 0 ||
                parse_int(b, &center_y) != 0 ||
                parse_int(c, &delta) != 0 ||
                (count >= 5 && parse_int(d, &steps) != 0)) {
                printf("ERR pinch usage: pinch <center_x> <center_y> <delta> [steps]\n");
                fflush(stdout);
                continue;
            }
            rc = send_pinch_sequence(handle, center_x, center_y, delta, steps);
        } else {
            printf("ERR unknown command\n");
            fflush(stdout);
            continue;
        }

        if (rc < 0) {
            printf("ERR %s\n", usb_error_name(rc));
        } else {
            printf("OK\n");
        }
        fflush(stdout);
    }

    return 0;
}

static int open_device(libusb_device *device, libusb_device_handle **handle) {
    int rc = libusb_open(device, handle);
    if (rc < 0) {
        return rc;
    }
    return 0;
}

static int wait_for_aoa_device(libusb_context *context, libusb_device **device) {
    for (int attempt = 0; attempt < 40 && !interrupted; attempt++) {
        libusb_device *candidate = find_android_candidate(context, true);
        if (candidate != NULL) {
            *device = candidate;
            return 0;
        }
        usleep(250000);
    }
    return LIBUSB_ERROR_TIMEOUT;
}

static void usage(const char *program) {
    printf("Usage: %s [--list] [--probe] [--start-aoa] [--hid-test] [--stdio]\n", program);
    printf("\n");
    printf("  --list       list USB Android/AOA candidates\n");
    printf("  --probe      read AOA protocol version from the first Android candidate\n");
    printf("  --start-aoa  switch the Android device into AOA mode\n");
    printf("  --hid-test   register keyboard/mouse HID and send a small test event\n");
    printf("  --stdio      keep HID open and accept stdin commands\n");
    printf("\n");
    printf("Notes:\n");
    printf("  --hid-test implies --start-aoa when the device is not already in AOA mode.\n");
    printf("  --stdio implies --start-aoa and registers keyboard/mouse HID.\n");
    printf("  AOA mode disconnects the current ADB session while the USB device re-enumerates.\n");
}

int main(int argc, char **argv) {
    bool do_list = false;
    bool do_probe = false;
    bool do_start_aoa = false;
    bool do_hid_test = false;
    bool do_stdio = false;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--list") == 0) {
            do_list = true;
        } else if (strcmp(argv[i], "--probe") == 0) {
            do_probe = true;
        } else if (strcmp(argv[i], "--start-aoa") == 0) {
            do_start_aoa = true;
        } else if (strcmp(argv[i], "--hid-test") == 0) {
            do_hid_test = true;
        } else if (strcmp(argv[i], "--stdio") == 0) {
            do_stdio = true;
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage(argv[0]);
            return 0;
        } else {
            fprintf(stderr, "unknown option: %s\n", argv[i]);
            usage(argv[0]);
            return 2;
        }
    }

    if (!do_list && !do_probe && !do_start_aoa && !do_hid_test) {
        do_list = true;
        do_probe = true;
    }
    if (do_hid_test) {
        do_start_aoa = true;
    }
    if (do_stdio) {
        do_start_aoa = true;
    }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    libusb_context *context = NULL;
    int rc = libusb_init(&context);
    if (rc < 0) {
        fprintf(stderr, "libusb_init failed: %s\n", usb_error_name(rc));
        return 1;
    }

    if (do_list) {
        libusb_device **devices = NULL;
        ssize_t count = libusb_get_device_list(context, &devices);
        if (count < 0) {
            fprintf(stderr, "libusb_get_device_list failed: %s\n", usb_error_name((int)count));
            libusb_exit(context);
            return 1;
        }

        printf("USB Android/AOA candidates:\n");
        for (ssize_t i = 0; i < count; i++) {
            struct libusb_device_descriptor descriptor;
            if (libusb_get_device_descriptor(devices[i], &descriptor) != 0) {
                continue;
            }
            if (descriptor.idVendor == 0x04e8 || descriptor.idVendor == GOOGLE_VENDOR_ID) {
                print_device(devices[i]);
            }
        }
        libusb_free_device_list(devices, 1);
    }

    libusb_device *device = find_android_candidate(context, false);
    if (device == NULL) {
        fprintf(stderr, "no Android USB candidate found\n");
        libusb_exit(context);
        return 1;
    }

    libusb_device_handle *handle = NULL;
    rc = open_device(device, &handle);
    if (rc < 0) {
        fprintf(stderr, "failed to open Android USB candidate: %s\n", usb_error_name(rc));
        libusb_unref_device(device);
        libusb_exit(context);
        return 1;
    }

    struct libusb_device_descriptor descriptor;
    rc = libusb_get_device_descriptor(device, &descriptor);
    if (rc < 0) {
        fprintf(stderr, "failed to read descriptor: %s\n", usb_error_name(rc));
        libusb_close(handle);
        libusb_unref_device(device);
        libusb_exit(context);
        return 1;
    }

    bool already_aoa = is_aoa_product(descriptor.idVendor, descriptor.idProduct);
    uint16_t protocol = 0;

    if (!already_aoa && (do_probe || do_start_aoa)) {
        rc = aoa_get_protocol(handle, &protocol);
        if (rc < 0) {
            fprintf(stderr, "AOA GET_PROTOCOL failed: %s\n", usb_error_name(rc));
            libusb_close(handle);
            libusb_unref_device(device);
            libusb_exit(context);
            return 1;
        }
        printf("AOA protocol version: %u\n", protocol);
        if (protocol < 2 && do_hid_test) {
            fprintf(stderr, "AOA protocol version %u does not support AOA2 HID\n", protocol);
            libusb_close(handle);
            libusb_unref_device(device);
            libusb_exit(context);
            return 1;
        }
    } else if (already_aoa) {
        printf("Device is already in AOA mode: vid=%04x pid=%04x\n", descriptor.idVendor, descriptor.idProduct);
    }

    if (do_start_aoa && !already_aoa) {
        const char *manufacturer = "MtoG";
        const char *model = "MtoG HID Bridge";
        const char *description = "Mac to Galaxy HID bridge";
        const char *version = "0.1";
        const char *uri = "https://localhost/mtog";
        const char *serial = "mtog-aoa-hid";

        printf("Requesting AOA mode. ADB will disconnect while USB re-enumerates.\n");
        aoa_send_string(handle, 0, manufacturer);
        aoa_send_string(handle, 1, model);
        aoa_send_string(handle, 2, description);
        aoa_send_string(handle, 3, version);
        aoa_send_string(handle, 4, uri);
        aoa_send_string(handle, 5, serial);

        rc = aoa_start(handle);
        if (rc < 0) {
            fprintf(stderr, "AOA START failed: %s\n", usb_error_name(rc));
            libusb_close(handle);
            libusb_unref_device(device);
            libusb_exit(context);
            return 1;
        }

        libusb_close(handle);
        libusb_unref_device(device);
        handle = NULL;
        device = NULL;

        rc = wait_for_aoa_device(context, &device);
        if (rc < 0) {
            fprintf(stderr, "timed out waiting for AOA re-enumeration: %s\n", usb_error_name(rc));
            libusb_exit(context);
            return 1;
        }

        rc = open_device(device, &handle);
        if (rc < 0) {
            fprintf(stderr, "failed to open AOA device: %s\n", usb_error_name(rc));
            libusb_unref_device(device);
            libusb_exit(context);
            return 1;
        }
        printf("AOA device opened after re-enumeration.\n");
    }

    if (do_hid_test || do_stdio) {
        printf("Registering AOA HID keyboard, mouse, and touch.\n");
        rc = register_hid_device(handle, HID_ID_KEYBOARD, keyboard_report_descriptor, sizeof(keyboard_report_descriptor));
        if (rc < 0) {
            fprintf(stderr, "keyboard HID registration failed: %s\n", usb_error_name(rc));
            libusb_close(handle);
            libusb_unref_device(device);
            libusb_exit(context);
            return 1;
        }

        rc = register_hid_device(handle, HID_ID_MOUSE, mouse_report_descriptor, sizeof(mouse_report_descriptor));
        if (rc < 0) {
            fprintf(stderr, "mouse HID registration failed: %s\n", usb_error_name(rc));
            libusb_close(handle);
            libusb_unref_device(device);
            libusb_exit(context);
            return 1;
        }

        rc = register_hid_device(handle, HID_ID_TOUCH, touch_report_descriptor, sizeof(touch_report_descriptor));
        if (rc < 0) {
            fprintf(stderr, "touch HID registration failed: %s\n", usb_error_name(rc));
            libusb_close(handle);
            libusb_unref_device(device);
            libusb_exit(context);
            return 1;
        }

        usleep(250000);

        if (do_stdio) {
            rc = run_stdio_loop(handle);
            libusb_close(handle);
            libusb_unref_device(device);
            libusb_exit(context);
            return rc == 0 ? 0 : 1;
        }

        printf("Sending mouse movement/click test.\n");
        rc = send_mouse_test(handle);
        if (rc < 0) {
            fprintf(stderr, "mouse HID event failed: %s\n", usb_error_name(rc));
            libusb_close(handle);
            libusb_unref_device(device);
            libusb_exit(context);
            return 1;
        }

        printf("Sending keyboard 'a' test. Focus a text field on Galaxy to see it.\n");
        rc = send_keyboard_a_test(handle);
        if (rc < 0) {
            fprintf(stderr, "keyboard HID event failed: %s\n", usb_error_name(rc));
            libusb_close(handle);
            libusb_unref_device(device);
            libusb_exit(context);
            return 1;
        }
    }

    libusb_close(handle);
    libusb_unref_device(device);
    libusb_exit(context);
    return 0;
}
