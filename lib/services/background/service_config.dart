class ServiceConfig {
  // Security: In production, consider moving this to an .env file
  static const String googleScriptUrl =
      "https://script.google.com/macros/s/AKfycbxO6aA5rbKY2zyDymVdZUJR4fa6YkCdhUXEmlrlfHzQlszF0HR3x8j7wnlwLDyO9h2D/exec";

  // Notification Channels
  static const String channelId = 'research_channel_01';
  static const String channelName = 'Data Collection Service';
  static const int notificationId = 888;
}
