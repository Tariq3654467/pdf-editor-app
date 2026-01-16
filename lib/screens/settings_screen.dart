import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_review/in_app_review.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedLanguage = 'English';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF263238)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Color(0xFF263238),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
          // Language option
          _buildSettingsTile(
            icon: Icons.description,
            title: 'Language',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selectedLanguage,
                  style: const TextStyle(
                    color: Color(0xFF263238),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.keyboard_arrow_down,
                  color: Color(0xFF9E9E9E),
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
    return ListTile(
      leading: Icon(
        icon,
        color: const Color(0xFF263238),
        size: 24,
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF263238),
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: trailing ?? const Icon(
        Icons.chevron_right,
        color: Color(0xFF9E9E9E),
        size: 20,
      ),
      onTap: onTap,
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

