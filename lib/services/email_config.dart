/// EmailJS settings for sending study plan emails straight from the app
/// (free, no Firebase Blaze plan needed). Fill these in from
/// https://dashboard.emailjs.com — see EMAIL_SETUP.md.
///
/// The public key is meant to be used in apps; it is not a password.
/// Leave any value empty to send through the Cloud Function instead.
class EmailConfig {
  static const serviceId = 'service_xbc5848'; // Email Services → e.g. service_ab12cd3
  static const templateId = 'template_tn0vvjk'; // Email Templates → e.g. template_xy98zt1
  static const publicKey = 'E8gzBmbZpR3yRiTuE'; // Account → General → Public Key

  static bool get useEmailJs => serviceId.isNotEmpty && templateId.isNotEmpty && publicKey.isNotEmpty;

  /// Plan emails per student per day (stops accidental floods).
  static const dailyLimit = 5;
}
