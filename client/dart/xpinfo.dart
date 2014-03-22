library xpinfo;

import "info.dart";
import "../shared/dart/gametypes.dart";

class XPInfo extends Info {

  String fillColor = "rgb(210, 216, 57, 0.94)";
  String strokeColor = "rgb(50, 120, 50)";
  Orientation orientation = Orientation.RIGHT;

  XPInfo(int id, String value, int x, int y): super(id, value, x, y);
}
