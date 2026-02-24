import re

with open('lib/features/webshare/presentation/widgets/web_rtc_connection_bottomsheet.dart', 'r') as f:
    content = f.read()

# Replace top part
target_top = """  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: AppSizes.spaceBtwInputFields * 0.5),
            // NetworkIndicator(networkName: _networkName),
            // const SizedBox(height: AppSizes.spaceBtwItems),
            ConnectionInstructions(),"""

replacement_top = """  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ConnectionInstructions(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: AppSizes.spaceBtwInputFields * 0.5),
                // NetworkIndicator(networkName: _networkName),
                // const SizedBox(height: AppSizes.spaceBtwItems),"""

content = content.replace(target_top, replacement_top)

# Replace bottom part
target_bottom = """            ],
          ],
        ),
      ),
    );
  }
}"""

replacement_bottom = """            ],
          ],
        ),
      ),
        ],
      ),
    );
  }
}"""

content = content.replace(target_bottom, replacement_bottom)

with open('lib/features/webshare/presentation/widgets/web_rtc_connection_bottomsheet.dart', 'w') as f:
    f.write(content)
