class ServiceConfig {
  // Security: In production, consider moving this to an .env file
  static const String googleScriptUrl =
      "https://script.google.com/macros/s/AKfycbyHA5394Trxj3DYwTsop2xwJeS07mmA3JUea_xc3ZxWcYhx_WZPpN9EwdSF936kl4ll/exec";

  // Notification Channels
  static const String channelId = 'research_channel_01';
  static const String channelName = 'Data Collection Service';
  static const int notificationId = 888;
}
