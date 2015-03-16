library chest;

import "dart:html";

import "entity.dart";
import "game.dart";
import "lib/gametypes.dart";

class Chest extends Entity {

  Chest(int id): super(id, Entities.CHEST);

  // TODO: remove eventually! sprites should be handled directly from the sprite member.
  String getSpriteName() => "chest";

  bool isMoving() => false;

  void open() {
    this.stopBlinking();

    // TODO: remove eventually! should be a boolean indicating 
    // that the sprite getter should return the death sprite.
    this.sprite = Game.sprites["death"];

    this.setAnimation("death", 120, 1, () {
      window.console.info("${this.id} was removed");

      Game.removeEntity(this);
      Game.removeFromRenderingGrid(this, this.gridPosition);
      Game.previousClickPosition = null;
    });
  }
}