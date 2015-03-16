library character;

import "dart:async";
import "dart:html";
import "dart:math";

import "entity.dart";
import "game.dart";
import "position.dart";
import "sprite.dart";
import "transition.dart";
import "lib/gametypes.dart";

class Character extends Entity {

  int _hp = 0;
  int _maxHP = 0;
  int _level = 0;

  EntityKind _weapon;
  EntityKind _armor;

  // Position and orientation
  int nextGridX = -1;
  int nextGridY = -1;
  Orientation orientation = Orientation.DOWN;

  // Speeds
  int atkSpeed = 50;
  int moveSpeed = 120;
  int walkSpeed = 100;
  int idleSpeed = 450;
  Timer attackCooldown;

  // Pathing
  Transition movement = new Transition();
  var path;
  int step = 0;
  Position destination;
  Position newDestination;
  var adjacentTiles = {};

  // Combat
  Character _target;
  Character unconfirmedTarget;
  Character previousTarget;
  Map<int, Character> attackers = {};

  // Modes
  bool isDead = false;
  bool isDying = false;
  bool isMovementInterrupted = false;
  bool attackingMode = false;
  bool followingMode = false;
  bool showWeapon = true;
  bool showArmor = true;

  bool isHurting = false;
  Timer hurtingTimer;

  Character(int id, EntityKind kind): super(id, kind);

  void reset() {
    super.reset();

    // Position and orientation
    this.nextGridX = -1;
    this.nextGridY = -1;
    this.orientation = Orientation.DOWN;

    // Speeds
    this.atkSpeed = 50;
    this.moveSpeed = 120;
    this.walkSpeed = 100;
    this.idleSpeed = 450;
    this.setAttackRate(800);

    // Pathing
    this.movement = new Transition();
    this.path = null;
    this.newDestination = null;
    this.adjacentTiles = {};

    // Combat
    this.target = null;
    this.unconfirmedTarget = null;
    this.attackers = new Map<int, Entity>();

    // Modes
    this.isDead = false;
    this.isDying = false;
    this.attackingMode = false;
    this.followingMode = false;
  }

  void clean() {
    super.clean();

    this.forEachAttacker((Character attacker) {
      attacker.disengage();
      attacker.idle();
    });
  }

  Sprite get sprite {
    var sprite = super.sprite;
    if (this.armor != null) {
      String kindString = Types.getKindAsString(this._armor);
      sprite = Game.sprites[kindString];
    }

    return this.isHurting ? sprite.getHurtSprite() : sprite;
  }

  bool isHostile(Entity entity) => false;

  Character get target => this._target;
  void set target(Character target) {
    this._target = target;
    this.trigger("TargetChange");
    // TODO: remove or uncomment
    // this.trigger("change");
  }

  int get hp => this._hp;
  void set hp(int hp) {
    this._hp = hp;
    this.trigger("HealthChange");
    this.trigger("change");
  }

  int get maxHP => this._maxHP;
  void set maxHP(int maxHP) {
    this._maxHP = maxHP;
    this.trigger("HealthChange");
    this.trigger("change");
  }

  int get level => this._level;
  void set level(int level) {
    this._level = level;
    this.trigger("LevelChange");
    this.trigger("change");
  }

  EntityKind get armor => this._armor;
  void set armor(EntityKind armor) {
    this._armor = armor;
    this.trigger("ArmorChange");
    this.trigger("EquipmentChange");
    this.trigger("change");
  }

  EntityKind get weapon => this._weapon;
  void set weapon(EntityKind weapon) {
    this._weapon = weapon;
    this.trigger("WeaponChange");
    this.trigger("EquipmentChange");
    this.trigger("change");
  }

  // TODO: remove completely the next four methods.
  // they serve no purpose and armor/weapon should have their own classes to retrieve such
  // information from, and not from some properties data structure.
  void equipArmor(EntityKind armor) {
    this.armor = armor;
  }
  void equipWeapon(EntityKind weapon) {
    this.weapon = weapon;
  }
  int getArmorRank() => Types.getArmorRank(this.armor);
  int getWeaponRank() => Types.getWeaponRank(this.weapon);

  bool hasWeapon() => this.weapon != null;

  void setDefaultAnimation() {
    this.idle();
  }

  bool hasShadow() => false;

  void animate(String animationName, int speed, [int count = 0, Function onEndCount]) {
    var oriented = ['atk', 'walk', 'idle'];

    // don't change animation if the character is dying
    if (this.currentAnimation != null && this.currentAnimation.name == "death" && this.isDying) {
      return;
    }

    this.flipSpriteX = false;
    this.flipSpriteY = false;

    if (oriented.contains(animationName)) {
      animationName += "_" + (this.orientation == Orientation.LEFT ? "right" : Types.getOrientationAsString(this.orientation));
      this.flipSpriteX = (this.orientation == Orientation.LEFT);
    }

    this.setAnimation(animationName, speed, count, onEndCount);
  }

  void turnTo(Orientation orientation) {
    this.orientation = orientation;
    this.idle();
  }

  void idle([Orientation orientation]) {
    if (orientation != null) {
      this.orientation = orientation;
    }

    this.animate("idle", this.idleSpeed);
  }

  void hit([Orientation orientation]) {
    if (orientation != null) {
      this.orientation = orientation;
    }

    this.animate("atk", this.atkSpeed, 1);
  }

  void walk([Orientation orientation]) {
    if (orientation != null) {
      this.orientation = orientation;
    }

    this.animate("walk", this.walkSpeed);
  }

  void moveTo_(Position position) {
    this.destination = position;
    this.adjacentTiles = {};

    if (this.isMoving()) {
      this.continueTo(position);
      return;
    }

    this.followPath(this.requestPathfindingTo(position));
  }

  // TODO: give a real type to paths
  requestPathfindingTo(Position position) {
    List<Entity> ignored = [];
    // Always ignore self
    ignored.add(this);

    // TODO: maybe we should stop ignoring the target??
    //       if we want to move to a location, we just want to get there asap.
    var target = this.hasTarget() ? this.target : this.previousTarget;
    if (target != null) {
      ignored.add(target);

      // TODO: maybe we should stop ignoring attackers of the target entity?
      //       it might be cool to make the attackers spread around the target entity,
      //       but that is not practical for a lot of attackers and looks pretty stupid
      //       not mentioning moving targets to locations where they are not really present

      // also ignore other attackers of the target entity
      target.forEachAttacker((Entity attacker) {
        ignored.add(attacker);
      });
    }

    return Game.findPath(this, position, ignored);
  }

  void startPathing(var path) {
  }

  void stopPathing(Position position) {
    if (this.isDying) {
      return;
    }

    if (this.hasTarget() && this.isAdjacent(this.target)) {
      this.lookAtTarget();
    }

    this.forEachAttacker((Character attacker) {
      if (!attacker.isAdjacentNonDiagonal(this) && attacker.id != this.id) {
        attacker.follow(this);
      }
    });

    Game.unregisterEntityPosition(this);
    Game.registerEntityPosition(this);
  }

  void followPath(List path) {
    if (path.length <= 1) { // Length of 1 means the player has clicked on himself
      return;
    }

    this.path = path;
    this.step = 0;

    if (this.followingMode) { // following a character
      path.removeLast();
    }

    this.startPathing(path);
    this.nextStep();
  }

  void continueTo(Position position) {
    this.newDestination = position;
  }

  void updateMovement() {
    if (this.path[this.step][0] < this.path[this.step - 1][0]) {
      this.walk(Orientation.LEFT);
    }
    if (this.path[this.step][0] > this.path[this.step - 1][0]) {
      this.walk(Orientation.RIGHT);
    }
    if (this.path[this.step][1] < this.path[this.step - 1][1]) {
      this.walk(Orientation.UP);
    }
    if (this.path[this.step][1] > this.path[this.step - 1][1]) {
      this.walk(Orientation.DOWN);
    }
  }

  void updatePositionOnGrid() {
    this.gridPosition = new Position(this.path[this.step][0], this.path[this.step][1]);
  }

  void nextStep() {
    bool stop = false;
    var path;

    if (!this.isMoving()) {
      return;
    }

    this.beforeStep();

    this.updatePositionOnGrid();
    this.checkAggro();

    if (this.isMovementInterrupted) { // if Character.stop() has been called
      stop = true;
      this.isMovementInterrupted = false;
    } else {
      if (this.hasNextStep()) {
        this.nextGridX = this.path[this.step + 1][0];
        this.nextGridY = this.path[this.step + 1][1];
      }

      this.doStep();

      if (this.hasChangedItsPath()) {
        path = this.requestPathfindingTo(this.newDestination);

        this.newDestination = null;
        if (path.length < 2) {
          stop = true;
        } else {
          this.followPath(path);
        }
      } else if (this.hasNextStep()) {
        this.step++;
        this.updateMovement();
      } else {
        stop = true;
      }
    }

    if (stop) { // Path is complete or has been interrupted
      this.path = null;
      this.idle();

      this.stopPathing(this.gridPosition);
    }
  }

  void beforeStep() {
    Game.unregisterEntityPosition(this);
  }

  void doStep() {
    if (this.isDying) {
      return;
    }

    Game.registerEntityDualPosition(this);

    this.forEachAttacker((attacker) {
      if (attacker.isAdjacent(attacker.target)) {
        attacker.lookAtTarget();
      } else {
        attacker.follow(this);
      }
    });
  }

  bool isMoving() => (this.path != null);

  bool hasNextStep() => (this.path.length - 1 > this.step);

  bool hasChangedItsPath() => (this.newDestination != null);

  bool isNear(Character character, num distance) =>
    (this.gridPosition.x - character.gridPosition.x).abs() <= distance
    && (this.gridPosition.y - character.gridPosition.y).abs() <= distance;

  checkAggro() {
  }

  aggro(Character character) {
  }

  void lookAtTarget() {
    if (this.hasTarget()) {
      this.turnTo(this.getOrientationTo(this.target));
    }
  }

  void go(Position position) {
    if (this.isAttacking()) {
      this.disengage();
    } else if (this.followingMode) {
      this.followingMode = false;
      this.target = null;
    }

    this.moveTo_(position);
  }

  void follow(Entity entity) {
    this.followingMode = true;
    this.moveTo_(entity.gridPosition);
  }

  void stop() {
    if (this.isMoving()) {
      this.isMovementInterrupted = true;
    }
  }

  /**
   * Makes the character attack another character. Same as Character.follow but with an auto-attacking behavior.
   * @see Character.follow
   */
  void engage(Character character) {
    this.attackingMode = true;
    this.setTarget(character);
    this.follow(character);
  }

  void disengage() {
    this.attackingMode = false;
    this.followingMode = false;
    this.removeTarget();
  }

  bool isAttacking() => this.attackingMode;

  /**
   * Gets the right orientation to face a target character from the current position.
   * Note:
   * In order to work properly, this method should be used in the following
   * situation :
   *    S
   *  S T S
   *    S
   * (where S is self, T is target character)
   *
   * @param {Character} character The character to face.
   * @returns {String} The orientation.
   */
  Orientation getOrientationTo(Character character) {
    if (this.gridPosition.x < character.gridPosition.x) {
      return Orientation.RIGHT;
    } else if (this.gridPosition.x > character.gridPosition.x) {
      return Orientation.LEFT;
    } else if (this.gridPosition.y > character.gridPosition.y) {
      return Orientation.UP;
    }

    return Orientation.DOWN;
  }

  bool isAttackedBy(character) => this.attackers.containsKey(character.id);

  void addAttacker(Character character) {
    this.attackers.putIfAbsent(character.id, () => character);
  }

  void removeAttacker(Character character) {
    this.attackers.remove(character.id);
  }

  /**
   * Loops through all the characters currently attacking this one.
   * @param {Function} callback Function which must accept one character argument.
   */
  void forEachAttacker(void callback(Character character)) {
    this.attackers.forEach((int id, Character character) {
      callback(character);
    });
  }

  void setTarget(Entity entity) {
    if (this.hasTarget() && this.target == entity) {
      // If it's not already set as the target
      return;
    }

    if (this.hasTarget()) {
      this.removeTarget(); // Cleanly remove the previous one
    }
    this.unconfirmedTarget = null;
    this.target = entity;
  }

  void removeTarget() {
    if (!this.hasTarget()) {
      return;
    }

    this.target.removeAttacker(this);
    this.target = null;
  }

  bool hasTarget() => (this.target != null);

  // TODO: figure out if this is needed. applies to the next two methods.
  /**
   * Marks this character as waiting to attack a target.
   * By sending an "attack" message, the server will later confirm (or not)
   * that this character is allowed to acquire this target.
   *
   * @param {Character} character The target character
   */
  void waitToAttack(Character character) {
    this.unconfirmedTarget = character;
  }
  bool isWaitingToAttack(Character character) => (this.unconfirmedTarget == character);

  bool canAttack(int time) =>
      this.canReachTarget()
      && (this.attackCooldown == null || this.attackCooldown.isActive);

  bool canReachTarget() => (this.hasTarget() && this.isAdjacentNonDiagonal(this.target));

  void die() {
    this.removeTarget();
    this.isDead = true;

    window.console.info("${this.id} is dead");

    this.isDying = true;
    this.setSprite(Game.sprites["death"]);

    this.animate("death", 120, 1, () {
      window.console.info("${this.id} was removed");

      Game.removeEntity(this);
      Game.removeFromRenderingGrid(this, this.gridPosition);
    });

    this.forEachAttacker((Character attacker) {
      attacker.disengage();
    });

    if (Game.player.target != null && Game.player.target.id == this.id) {
      Game.player.disengage();
    }

    // Upon death, this entity is removed from both grids, allowing the player
    // to click very fast in order to loot the dropped item and not be blocked.
    // The entity is completely removed only after the death animation has ended.
    Game.removeFromEntityGrid(this, this.gridPosition);
    Game.removeFromPathingGrid(this.gridPosition);

    if (Game.camera.isVisible(this)) {
      var rng = new Random();
      Game.audioManager.playSound("kill${rng.nextInt(2)+1}");
    }

    Game.updateCursor();
  }

  // TODO: can this turn into .on/.trigger event?
  void moved() {
    this.dirty();

    // Make chat bubbles follow moving entities
    Game.assignBubbleTo(this);
  }

  void hurt() {
    this.stopHurting();
    this.isHurting = true;
    this.hurtingTimer = new Timer(new Duration(milliseconds: 75), this.stopHurting);
  }

  void stopHurting() {
    this.isHurting = false;
    if (this.hurtingTimer != null && this.hurtingTimer.isActive) {
      this.hurtingTimer.cancel();
    }
  }

  // TODO: figure out all the usages of this method. we might be better off
  // with just calculating it off this.atkRate (to be created),
  // and launching the timer only after an attack so we don't have it running
  // for each mob all the time.
  void setAttackRate(rate) {
    this.attackCooldown = new Timer(new Duration(milliseconds: rate), () {});
  }
}