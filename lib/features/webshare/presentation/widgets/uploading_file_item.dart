import 'package:cpft/features/webshare/presentation/webshare_screen.dart';
import 'package:cpft/features/webshare/presentation/widgets/upload_progress.dart';

class UploadingFileItem extends FileListItem {
  final UploadProgress progress;
  UploadingFileItem(this.progress);
}
