import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/theme.dart';
import '../../../core/theme_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _pickImage(WidgetRef ref, BuildContext context) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      final uid = ref.read(currentUserProvider)?.uid;
      if (uid != null) {
        try {
          final bytes = await image.readAsBytes();
          final url = await ref.read(firebaseServiceProvider).uploadFile(
            uid, image.name, bytes, 'image/jpeg'
          );
          await ref.read(firebaseServiceProvider).updateProfilePicture(uid, url);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile picture updated!'))
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Upload failed: $e'))
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: AppTheme.pastelLavender,
                  backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                  child: user?.photoURL == null 
                    ? Text(
                        (user?.displayName != null && user!.displayName!.isNotEmpty)
                            ? user.displayName!.substring(0, 1).toUpperCase()
                            : 'U',
                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFFAD1457)))
                    : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    backgroundColor: const Color(0xFFAD1457),
                    child: IconButton(
                      icon: const Icon(Icons.camera_alt, color: Colors.white),
                      onPressed: () => _pickImage(ref, context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ListTile(
            title: const Text('Name', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(user?.displayName ?? 'Not set'),
            leading: const Icon(Icons.person_outline),
          ),
          ListTile(
            title: const Text('Email', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(user?.email ?? ''),
            leading: const Icon(Icons.email_outlined),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Switch between light and dark themes'),
            secondary: Icon(themeMode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode),
            value: themeMode == ThemeMode.dark,
            onChanged: (v) => ref.read(themeModeProvider.notifier).toggleTheme(),
          ),
        ],
      ),
    );
  }
}
