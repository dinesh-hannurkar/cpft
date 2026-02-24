import re

with open('lib/features/webshare/presentation/web_room_entry_screen.dart', 'r') as f:
    content = f.read()

target_top = """            child: SafeArea(
              child: Center(
                child: Padding("""
replacement_top = """            child: SafeArea(
              child: Column(
                children: [
                  StatusBanner(
                    color: Colors.blue.shade50,
                    borderColor: Colors.blue.shade200,
                    iconColor: AppColors.primary,
                    icon: Icons.info_outline,
                    title: 'Connection Required',
                    subtitle:
                        'Ensure both devices are on the same Wi‑Fi or Personal Hotspot.',
                  ),
                  Expanded(
                    child: Center(
                      child: Padding("""

content = content.replace(target_top, replacement_top)

target_bottom = """                          const SizedBox(height: AppSizes.md),
                          StatusBanner(
                            color: Colors.blue.shade50,
                            borderColor: Colors.blue.shade200,
                            iconColor: AppColors.primary,
                            icon: Icons.info_outline,
                            title: 'Connection Required',
                            subtitle:
                                'Ensure both devices are on the same Wi‑Fi or Personal Hotspot.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}"""
replacement_bottom = """                        ],
                      ),
                    ),
                  ),
                ),
              ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}"""

content = content.replace(target_bottom, replacement_bottom)

with open('lib/features/webshare/presentation/web_room_entry_screen.dart', 'w') as f:
    f.write(content)
