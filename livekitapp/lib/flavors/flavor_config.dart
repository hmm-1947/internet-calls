enum AppFlavor { user, listener }

class FlavorConfig {
  static late AppFlavor flavor;

  static bool get isUser => flavor == AppFlavor.user;
  static bool get isListener => flavor == AppFlavor.listener;

  static void set(AppFlavor f) {
    flavor = f;
  }
}
