import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_review/in_app_review.dart';
import '../services/theme_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedLanguage = 'English';
  ThemeMode _currentThemeMode = ThemeMode.system;
  
  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }
  
  Future<void> _loadThemeMode() async {
    final themeMode = await ThemeService.getThemeMode();
    if (mounted) {
      setState(() {
        _currentThemeMode = themeMode;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ThemeService.isDarkMode(context);
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    final iconColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: iconColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            color: textColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Upgrade Premium Banner
              _buildPremiumBanner(),
              const SizedBox(height: 24),
              // Settings Options
              _buildSettingsCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumBanner() {
    final isDarkMode = ThemeService.isDarkMode(context);
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3), // Blue background
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: _upgradePremium,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            // Crown icon with lightning bolt
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.workspace_premium,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Upgrade Premium',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Become Premium member.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            // Arrow icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    final isDarkMode = ThemeService.isDarkMode(context);
    final cardColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Theme option
          _buildSettingsTile(
            icon: Icons.dark_mode,
            title: 'Theme',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getThemeModeText(),
                  style: TextStyle(
                    color: ThemeService.isDarkMode(context) 
                        ? Colors.white 
                        : const Color(0xFF263238),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: ThemeService.isDarkMode(context)
                      ? Colors.white70
                      : const Color(0xFF9E9E9E),
                  size: 20,
                ),
              ],
            ),
            onTap: _showThemeDialog,
          ),
          const Divider(height: 1, indent: 60),
          // Language option
          _buildSettingsTile(
            icon: Icons.description,
            title: 'Language',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selectedLanguage,
                  style: TextStyle(
                    color: ThemeService.isDarkMode(context)
                        ? Colors.white
                        : const Color(0xFF263238),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: ThemeService.isDarkMode(context)
                      ? Colors.white70
                      : const Color(0xFF9E9E9E),
                  size: 20,
                ),
              ],
            ),
            onTap: _showLanguageDialog,
          ),
          const Divider(height: 1, indent: 60),
          // Rate app option
          _buildSettingsTile(
            icon: Icons.star_outline,
            title: 'Rate app',
            onTap: _rateApp,
          ),
          const Divider(height: 1, indent: 60),
          // Share app option
          _buildSettingsTile(
            icon: Icons.share,
            title: 'Share app',
            onTap: _shareApp,
          ),
          const Divider(height: 1, indent: 60),
          // Privacy Policy option
          _buildSettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            onTap: _openPrivacyPolicy,
          ),
          const Divider(height: 1, indent: 60),
          // Terms of Use option
          _buildSettingsTile(
            icon: Icons.description_outlined,
            title: 'Terms of Use',
            onTap: _openTermsOfUse,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final isDarkMode = ThemeService.isDarkMode(context);
    final iconColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    final trailingColor = isDarkMode ? Colors.white70 : const Color(0xFF9E9E9E);
    
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor,
        size: 24,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: textColor,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: trailing ?? Icon(
        Icons.chevron_right,
        color: trailingColor,
        size: 20,
      ),
      onTap: onTap,
    );
  }
  
  String _getThemeModeText() {
    switch (_currentThemeMode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
      default:
        return 'System';
    }
  }
  
  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final isDarkMode = ThemeService.isDarkMode(context);
        final backgroundColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
        
        return Theme(
          data: Theme.of(context).copyWith(
            dialogBackgroundColor: backgroundColor,
          ),
          child: AlertDialog(
            title: Text('Select Theme', style: TextStyle(color: textColor)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildThemeOption('System', ThemeMode.system, Icons.brightness_auto),
                _buildThemeOption('Light', ThemeMode.light, Icons.light_mode),
                _buildThemeOption('Dark', ThemeMode.dark, Icons.dark_mode),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildThemeOption(String label, ThemeMode themeMode, IconData icon) {
    final isDarkMode = ThemeService.isDarkMode(context);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF263238);
    final isSelected = _currentThemeMode == themeMode;
    
    return ListTile(
      leading: Icon(icon, color: isSelected ? const Color(0xFFE53935) : textColor),
      title: Text(label, style: TextStyle(color: textColor)),
      trailing: isSelected
          ? const Icon(Icons.check, color: Color(0xFFE53935))
          : null,
      onTap: () async {
        setState(() {
          _currentThemeMode = themeMode;
        });
        await ThemeService.setThemeMode(themeMode);
        Navigator.pop(context);
        // Trigger app rebuild by showing a snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Theme changed to $label'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
        // Force app to rebuild with new theme
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Language'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageOption('English'),
            _buildLanguageOption('Spanish'),
            _buildLanguageOption('French'),
            _buildLanguageOption('German'),
            _buildLanguageOption('Chinese'),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption(String language) {
    final isSelected = _selectedLanguage == language;
    return ListTile(
      title: Text(language),
      trailing: isSelected
          ? const Icon(Icons.check, color: Color(0xFF2196F3))
          : null,
      onTap: () {
        setState(() {
          _selectedLanguage = language;
        });
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Language changed to $language'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  Future<void> _rateApp() async {
    final InAppReview inAppReview = InAppReview.instance;
    if (await inAppReview.isAvailable()) {
      inAppReview.requestReview();
    } else {
      // Fallback: Open app store page
      final appId = 'com.example.pdf_editor_app'; // Replace with your actual app ID
      final url = Uri.parse(
        'https://play.google.com/store/apps/details?id=$appId',
      );
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to open app store'),
            ),
          );
        }
      }
    }
  }

  Future<void> _shareApp() async {
    try {
      await Share.share(
        'Check out this amazing PDF Reader app!',
        subject: 'PDF Reader App',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing app: $e'),
          ),
        );
      }
    }
  }

  Future<void> _openPrivacyPolicy() async {
    // Replace with your actual privacy policy URL
    final url = Uri.parse('https://example.com/privacy-policy');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open privacy policy'),
          ),
        );
      }
    }
  }

  Future<void> _openTermsOfUse() async {
    // Replace with your actual terms of use URL
    final url = Uri.parse('https://example.com/terms-of-use');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open terms of use'),
          ),
        );
      }
    }
  }

  void _upgradePremium() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upgrade to Premium'),
        content: const Text(
          'Unlock all premium features:\n\n'
          '• Unlimited PDF editing\n'
          '• Remove watermarks\n'
          '• Advanced annotation tools\n'
          '• Priority support\n'
          '• Ad-free experience',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Premium upgrade feature coming soon!'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
            ),
            child: const Text(
              'Upgrade',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

