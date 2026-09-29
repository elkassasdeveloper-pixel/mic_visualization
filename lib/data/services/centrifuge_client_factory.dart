import 'package:centrifuge/centrifuge.dart' as centrifuge;
import 'package:mic_visualization/core/constants/centrifuge_config.dart';

class CentrifugeClientFactory {
  centrifuge.Client createClient(String userJwtToken) {
    return centrifuge.createClient(
      CentrifugeConfig.url,
      centrifuge.ClientConfig(
        getToken: (centrifuge.ConnectionTokenEvent event) async => userJwtToken,
      ),
    );
  }
}