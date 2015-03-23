library mob;

import "character.dart";
import "entity.dart";
import "game.dart";
import "player.dart";
import "lib/gametypes.dart";

class Mob extends Character {

  bool isAggressive = true;
  bool targetable = true;

  Mob(int id, EntityKind kind): super(id, kind);

  bool isHostile(Entity entity) => (entity is Player);

  void die() {
    // TODO(death): implement a proper function receive deathpositions @ Game class
    // Keep track of where mobs die in order to spawn their dropped items
    // at the right position later.
    Game.deathpositions[this.id] = this.gridPosition;

    super.die();
  }
}
