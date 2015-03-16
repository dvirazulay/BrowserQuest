library gameclient;

import "dart:async";
import "dart:convert";
import "dart:html" as html;

import "base.dart";
import "character.dart";
import "chat.dart";
import "chest.dart";
import "damageinfo.dart";
import "entityfactory.dart";
import "game.dart";
import "inventoryitem.dart";
import "item.dart";
import "mob.dart";
import "party.dart";
import "player.dart";
import "position.dart";
import "spell.dart";
import "spelleffect.dart";
import "lib/gametypes.dart";
import 'xpinfo.dart';
import 'entity.dart';

class GameClient extends Base {

  String host;
  int port;
  Chat chat;
  bool isListening = false;
  bool isTimeout = false;
  html.WebSocket connection;

  GameClient(String this.host, int this.port) {
    this.chat = new Chat();
    this.enable();

    this.on('Message.${Message.WELCOME.index}', (data) {
      this.trigger("Welcome", [data[1]]);
    });

    this.on('Message.${Message.MOVE.index}', (data) {
      int id = data[1];
      if (data[2] == null || data[3] == null) {
        throw new Exception("Move coordinates cannot be null. (${data})"); 
      }
      Position position = new Position(data[2], data[3]);

      if (Game.player != null && id != Game.player.id) {
        Entity entity = Game.getEntityByID(id);
        if (entity != null) {
          if (entity is Character) {
            if (Game.player.isAttackedBy(entity)) {
              Game.tryUnlockingAchievement("COWARD");
            }
            entity.disengage();
            entity.idle();
            Game.makeCharacterGoTo(entity, position);
          }
        } else {
          // TODO: this seems like a hack that was made for party updates. remove it
          // maybe it's a player location update
          // check if it's a player entity
          Player player = Game.getPlayerByID(id);
          if (player != null) {
            player.gridPosition = position;
          }
        }
      }
    });

    this.on('Message.${Message.LOOTMOVE.index}', (data) {
      int playerId = data[1];
      int itemId = data[2];

      Player player;
      Item item;
      if (playerId != Game.player.id) {
        player = Game.getEntityByID(playerId);
        item = Game.getEntityByID(itemId);

        if (player != null && item != null) {
          Game.makeCharacterGoTo(player, item.gridPosition);
        }
      }
    });

    this.on('Message.${Message.LOOT.index}', (data) {
      var itemId = data[1];

      var item = Game.player.inventory.find(itemId);
      if (!item) {
        html.window.console.error("Loot was picked up but couldn't be found in inventory. (${itemId})");
        return;
      }

      try {
        Game.player.loot(item);
        Game.showNotification(item.lootMessage);

        if (item.type == "armor") {
          Game.tryUnlockingAchievement("FAT_LOOT");
        }

        if (item.type == "weapon") {
          Game.tryUnlockingAchievement("A_TRUE_WARRIOR");
        }

        if (item.kind == Entities.CAKE) {
          Game.tryUnlockingAchievement("FOR_SCIENCE");
        }

        if (item.kind == Entities.FIREPOTION) {
          Game.tryUnlockingAchievement("FOXY");
          Game.audioManager.playSound("firefox");
        }

        if (Types.isHealingItem(item.kind)) {
          Game.audioManager.playSound("heal");
        } else {
          Game.audioManager.playSound("loot");
        }

        if (item.wasDropped && !item.playersInvolved.contains(Game.player.id)) {
          Game.tryUnlockingAchievement("NINJA_LOOT");
        }
      } catch (e) {
        // TODO: find a better way to do this and remove the comments
        /*if (e instanceof Exceptions.LootException) {*/
          /*Game.showNotification(e.message);*/
          /*Game.audioManager.playSound("noloot");*/
        /*} else {*/
          throw e;
        /*}*/
      }
    });

    this.on('Message.${Message.PARTY_JOIN.index}', (data) {
      Player player = Game.getPlayerByID(data[1]);

      Game.player.party.joined(player);
    });

    this.on('Message.${Message.PARTY_INITIAL_JOIN.index}', (data) {
      var leaderID = data[1];
      var membersIDs = data[2];

      Game.player.party = new Party(leaderID, Game.getPlayersByIDs(membersIDs));
    });

    this.on('Message.${Message.PARTY_LEAVE.index}', (data) {
      Player player = Game.getPlayerByID(data[1]);

      Game.player.party.left(player);
    });

    this.on('Message.${Message.PARTY_INVITE.index}', (data) {
      var inviter = Game.getPlayerByID(data[1]);
      var invitee = Game.getPlayerByID(data[2]);

      if (invitee == Game.player) {
        if (Game.player.party != null) {
          // already in a party.
          this.notice("You were invited to a party by ${inviter.name} but you are already in one. ('/leave' to leave it)");
          return;
        }

        this.notice("You were invited to a party by ${inviter.name}. '/accept ${inviter.name}' to join him.");
        return;
      }

      // this is a message about the party leader inviting someone to the
      // party.
      this.notice("${inviter.name} invited ${invitee.name} to join your party.");
    });

    this.on('Message.${Message.PARTY_KICK.index}', (data) {
      var kicker = Game.getPlayerByID(data[1]);
      var kicked = Game.getPlayerByID(data[2]);

      Game.player.party.kicked(kicker, kicked);
    });

    this.on('Message.${Message.PARTY_LEADER_CHANGE.index}', (data) {
      Player player = Game.getPlayerByID(data[1]);

      Game.player.party.setLeader(player);
    });

    this.on('Message.${Message.GUILD_INVITE.index}', (data) {
      var inviterName = data[1];
      String guildName = data[2];

      this.notice("You were invited to join the guild '${guildName}' by ${inviterName}. '/gaccept ${inviterName}' to accept.");
      return;
    });

    this.on('Message.${Message.GUILD_KICK.index}', (data) {
      var kickerName = data[1];
      var kickedName = data[2];

      if (kickedName == Game.player.name) {
        this.notice("You were kicked from the guild by ${kickerName}.");
      } else {
        this.notice("${kickedName} was kicked from the guild by ${kickerName}.");
      }
    });

    this.on('Message.${Message.GUILD_JOINED.index}', (data) {
      String playerName = data[1];
      String guildName = data[2];

      if (playerName == Game.player.name) {
        this.notice("You have joined the guild ${guildName}.");
      } else {
        this.notice("${playerName} has joined the guild.");
      }
    });

    this.on('Message.${Message.GUILD_LEFT.index}', (data) {
      String playerName = data[1];
      String guildName = data[2];

      if (playerName == Game.player.name) {
        this.notice("You have left the guild ${guildName}.");
      } else {
        this.notice("${playerName} has left the guild.");
      }
    });

    this.on('Message.${Message.GUILD_ONLINE.index}', (data) {
      String playerName = data[1];

      if (playerName == Game.player.name) {
        // don't report the online status to the player itself
        return;
      }

      this.notice("${playerName} has come online.");
    });

    this.on('Message.${Message.GUILD_OFFLINE.index}', (data) {
      String playerName = data[1];

      if (playerName == Game.player.name) {
        // don't report the online status to the player itself
        return;
      }

      this.notice("${playerName} went offline.");
    });

    this.on('Message.${Message.GUILD_MEMBERS.index}', (data) {
      // @TODO: move to a config
      var rankToTitle = {0: "Leader", 1: "Member", 2: "Officer"};

      var members = data[1];
      this.notice("Members of ${Game.player.guild.name}:");
      for (var i in members) {
        this.notice("${members[i].name} (${rankToTitle[members[i].rank]}) ${(members[i].online ? ' - Online' : '')}");
      }
    });

    this.on('Message.${Message.COMMAND_NOTICE.index}', (data) {
      var noticeMessage = data[1];
      this.notice(noticeMessage);
    });

    this.on('Message.${Message.COMMAND_ERROR.index}', (data) {
      var errorMessage = data[1];
      this.error(errorMessage);
    });

    this.on('Message.${Message.ERROR.index}', (data) {
      var errorMessage = data[1];
      this.error(errorMessage);
    });

    this.on('Message.${Message.ATTACK.index}', (data) {
      var attackerId = data[1],
        targetId = data[2];

      var attacker = Game.getEntityByID(attackerId),
        target = Game.getEntityByID(targetId);

      if (attacker != null && target != null && attacker.id != Game.player.id) {
        html.window.console.debug('${attacker.id} attacks ${target.id}');

        if (target is Player && target.id != Game.player.id && target.target != null&& target.target.id == attacker.id && attacker.getDistanceToEntity(target) < 3) {
          // TODO: eh? remove this crap and let the server decide on this AI behavior

          // delay to prevent other players attacking mobs
          // from ending up on the same tile as they walk
          // towards each other.
          new Timer(new Duration(milliseconds: 200), () {
            Game.createAttackLink(attacker, target);
          });
        } else {
          Game.createAttackLink(attacker, target);
        }
      }
    });

    this.on('Message.${Message.PLAYERS.index}', (data) {
      data[1].forEach((dynamic playerData) {
        this.handlePlayerEnter(playerData);
      });
    });

    this.on('Message.${Message.PLAYER_ENTER.index}', (data) {
      this.handlePlayerEnter(data[1]);
    });

    this.on('Message.${Message.PLAYER_UPDATE.index}', (data) {
      var playerData = data[1];
      Player player = Game.getPlayerByID(playerData.id);
      if (player == null || player.id == Game.player.id) {
        // irrelevant update
        return;
      }

      player.loadFromObject(playerData.data);
    });

    this.on('Message.${Message.PLAYER_EXIT.index}', (data) {
      int id = data[1];

      Game.removePlayer(id);
    });

    this.on('Message.${Message.SPAWN.index}', (data) {
      int id = data[1];
      EntityKind kind = Entities.get(data[2]);

      if (data[3] == null || data[4] == null) {
        throw new Exception("Spawn coordinates cannot be null. (${data})"); 
      }
      Position position = new Position(data[3], data[4]);

      if (Types.isSpell(kind)) {
        //@TODO: handle properly
//        Entity spell = EntityFactory.createEntity(kind, id);
      } else if (Types.isItem(kind)) {
        var item = EntityFactory.createEntity(kind, id);

        html.window.console.info("Spawned ${Types.getKindAsString(item.kind)} (${item.id}) at ${position}");
        Game.addItem(item, position);
      } else if (Types.isChest(kind)) {
        var chest = EntityFactory.createEntity(kind, id);

        html.window.console.info("Spawned chest (${chest.id}) at ${position}");
        chest.setSprite(Game.sprites[chest.getSpriteName()]);
        chest.gridPosition = position;
        chest.setAnimation("idle_down", 150);
        Game.addEntity(chest);
      } else if (Types.isNpc(kind)) {
        var npc = EntityFactory.createEntity(kind, id);

        html.window.console.info("Spawned ${Types.getKindAsString(npc.kind)} (${npc.id}) at ${npc.gridPosition}");
        npc.setSprite(Game.sprites[npc.getSpriteName()]);
        npc.gridPosition = position;
        npc.setAnimation("idle_down", 150);
        Game.addEntity(npc);
      } else {
        String name;
        EntityKind weapon;
        EntityKind armor;

        int hp = data[5];
        int maxHP = data[6];
        Orientation orientation = Orientations.get(data[7]);
        int targetId = data[8];

        Character character;
        if (Types.isPlayer(kind)) {
          name = data[9];
          armor = Entities.get(data[10]);
          weapon = Entities.get(data[11]);

          // get existing player entity
          character = Game.getPlayerByID(id);
          character.reset();
        } else {
          character = EntityFactory.createEntity(kind, id, name);
        }

        character.hp = hp;
        character.maxHP = maxHP;

        if (character is Player) {
          character.equipWeapon(weapon);
          character.equipArmor(armor);
        }

        if (!Game.entityIdExists(character.id)) {
          try {
            if (character.id != Game.player.id) {
              String kindString = Types.getKindAsString(character.skin);
              character.setSprite(Game.sprites[kindString]);
              character.gridPosition = position;
              character.orientation = orientation;
              character.idle();

              Game.addEntity(character);

              html.window.console.info("Spawned ${Types.getKindAsString(character.kind)} (${character.id}) at ${character.gridPosition}");

              if (character is Mob) {
                if (targetId != null) {
                  Player player = Game.getEntityByID(targetId);
                  if (player != null) {
                    Game.createAttackLink(character, player);
                  }
                }
              }
            }
          } catch (exception, stackTrace) {
            html.window.console.error("ReceiveSpawn failed. Error: ${exception}");
            html.window.console.error(stackTrace);
          }
        } else {
          html.window.console.debug("Character ${character.id} already exists. Don't respawn.");
        }
      }
    });

    this.on('Message.${Message.DESPAWN.index}', (data) {
      int id = data[1];

      if (!Game.entityIdExists(id)) {
        // entity was already removed
        html.window.console.log("Tried to remove an entity that was already removed. (id=${id})");
        return;
      }

      Entity entity = Game.getEntityByID(id);

      entity.isRemoved = true;

      html.window.console.info("Despawning ${Types.getKindAsString(entity.kind)} (${entity.id})");

      if (entity.gridPosition == Game.previousClickPosition) {
        Game.previousClickPosition = null;
      }

      if (entity is SpellEffect) {
        Game.removeSpellEffect(entity);
      } else if (entity is Item) {
        Game.removeItem(entity);
      } else if (entity is Character) {
        entity.forEachAttacker((attacker) {
          if (attacker.canReachTarget()) {
            attacker.hit();
          }
        });
        entity.die();
      } else if (entity is Chest) {
        entity.open();
      }

      entity.clean();
    });

    this.on('Message.${Message.HEALTH.index}', (data) {
      var entityId = data[1],
        hp = data[2],
        maxHP = data[3],
        isRegen = data[4] ? true : false;

      if (!Game.entityIdExists(entityId)) {
        html.window.console.debug("Received HEALTH message for an entity that doesn't exist. (id=${entityId})");
        return;
      }

      Character entity = Game.getEntityByID(entityId);
      var diff = hp - entity.hp;

      entity.maxHP = maxHP;
      entity.hp = hp;

      if (entityId == Game.player.id) {
        Player player = Game.player;
        bool isHurt = diff < 0;

        if (player != null && !player.isDead && !player.isInvincible) {
          //if (player.hp <= 0) {
          //player.die();
          //}
          if (isHurt) {
            player.hurt();
            Game.infoManager.addInfo(new ReceivedDamageInfo('${diff}', player.x, player.y - 15));
            Game.audioManager.playSound("hurt");
            // TODO: implement differently
//            Game.storage.addDamage(-diff);
            Game.tryUnlockingAchievement("MEATSHIELD");
            Game.events.trigger("Hurt");
          } else if (!isRegen) {
            Game.infoManager.addInfo(new HealedDamageInfo('+${diff}', player.x, player.y - 15));
          }
        }
        }
    });

    this.on('Message.${Message.CHAT.index}', (data) {
      var playerID = data[1],
        message = data[2],
        channel = data[3],
        playerName = data[4];

      Player player = Game.getPlayerByID(playerID);

      if (channel == "say" || channel == "yell") {
        Game.createBubble(player, message);
        Game.assignBubbleTo(player);
      }

      Game.audioManager.playSound("chat");

      var namePrefix = "";
      if (channel == "party" && Game.player.party != null && Game.player.party.isLeader(player)) {
        namePrefix = "\u2694 ";
      }

      this.chat.insertMessage(message, channel, player, namePrefix);
    });

    this.on('Message.${Message.EQUIP.index}', (data) {
      var playerId = data[1],
        itemKind = Entities.get(data[2]);

      var player = Game.getEntityByID(playerId),
        itemName = Types.getKindAsString(itemKind);

      if (player != null) {
        player.equip(itemKind);
      }
    });

    this.on('Message.${Message.DROP.index}', (data) {
      var entityId = data[1],
        id = data[2],
        kind = Entities.get(data[3]);

      var item = EntityFactory.createEntity(kind, id);
      item.wasDropped = true;
      item.playersInvolved = data[4];

      var pos = data[5];
      if (!pos) {
        pos = Game.getDeadMobPosition(entityId);
      }

      Game.addItem(item, pos);
      Game.updateCursor();
    });

    this.on('Message.${Message.TELEPORT.index}', (data) {
      int id = data[1];
      if (data[2] == null || data[3] == null) {
        throw new Exception("Teleport coordinates cannot be null. (${data})"); 
      }
      Position position = new Position(data[2], data[3]);

      if (id != Game.player.id) {
        Character entity = Game.getEntityByID(id);
        Orientation currentOrientation = entity.orientation;

        Game.makeCharacterTeleportTo(entity, position);
        entity.orientation = currentOrientation;

        entity.forEachAttacker((attacker) {
          attacker.disengage();
          attacker.idle();
          attacker.stop();
        });
      }
    });

    this.on('Message.${Message.DAMAGE.index}', (data) {
      var entityId = data[1],
        points = data[2],
        attackerId = data[3];

      Entity entity = Game.getEntityByID(entityId);
      if (attackerId == Game.player.id) {
        Game.infoManager.addInfo(new InflictedDamageInfo(points, entity.x, entity.y - 15));
      } else if (entityId == Game.player.id) {
        Game.infoManager.addInfo(new ReceivedDamageInfo(-points, Game.player.x, Game.player.y - 15));
      }
    });

    this.on('Message.${Message.POPULATION.index}', (data) {
      var worldPlayers = data[1],
        totalPlayers = data[2];

      var setWorldPlayersString = (String str) {
        html.document.querySelector("#instance-population span:nth-child(2)").text = str;
        html.document.querySelector("#playercount span:nth-child(2)").text = str;
      },
        setTotalPlayersString = (String str) {
        html.document.querySelector("#world-population span:nth-child(2)").text = str;
        };

      html.document.querySelector("#playercount span.count").text = '${worldPlayers}';

      html.document.querySelector("#instance-population span").text = '${worldPlayers}';
      if (worldPlayers == 1) {
        setWorldPlayersString("player");
      } else {
        setWorldPlayersString("players");
      }

      html.document.querySelector("#world-population span").text = '${totalPlayers}';
      if (totalPlayers == 1) {
        setTotalPlayersString("player");
      } else {
        setTotalPlayersString("players");
      }
    });

    this.on('Message.${Message.KILL.index}', (data) {
      EntityKind kind = Entities.get(data[1]);
      String mobName = Types.getKindAsString(kind);

      if (mobName == 'skeleton2') {
        mobName = 'greater skeleton';
      }

      if (mobName == 'eye') {
        mobName = 'evil eye';
      }

      if (mobName == 'deathknight') {
        mobName = 'death knight';
      }

      if (mobName == 'boss') {
        Game.showNotification("You killed the skeleton king");
      } else {
        if (['a', 'e', 'i', 'o', 'u'].contains(mobName[0])) {
          Game.showNotification("You killed an ${mobName}");
        } else {
          Game.showNotification("You killed a ${mobName}");
        }
      }

      // TODO: implement differently
//      Game.storage.incrementTotalKills();
      Game.tryUnlockingAchievement("HUNTER");

      if (kind == Entities.RAT) {
        // TODO: implement differently
//        Game.storage.incrementRatCount();
        Game.tryUnlockingAchievement("ANGRY_RATS");
      }

      if (kind == Entities.SKELETON || kind == Entities.SKELETON2) {
        // TODO: implement differently
//        Game.storage.incrementSkeletonCount();
        Game.tryUnlockingAchievement("SKULL_COLLECTOR");
      }

      if (kind == Entities.BOSS) {
        Game.tryUnlockingAchievement("HERO");
      }
    });

    this.on('Message.${Message.DEFEATED.index}', (data) {
      var actualData = data[1];
      this.notice("*** ${actualData.attackerName} has defeated ${actualData.victimName} (${actualData.x}, ${actualData.y}) ***");
    });

    this.on('Message.${Message.LIST.index}', (data) {
      data.removeAt(0);

      this.trigger("EntityList", [data]);
    });

    this.on('Message.${Message.DESTROY.index}', (data) {
      int id = data[1];

      if (!Game.entityIdExists(id)) {
        html.window.console.debug("Entity was already destroyed. (id=${id})");
        return;
      }

      Entity entity = Game.getEntityByID(id);
      if (entity is Item) {
        Game.removeItem(entity);
      } else {
        Game.removeEntity(entity);
      }

      html.window.console.debug("Entity was destroyed. (id=${entity.id})");
    });

    this.on('Message.${Message.XP.index}', (data) {
      var xp = data[1],
        maxXP = data[2],
        gainedXP = data[3];

      Player player = Game.player;
      player.xp = xp;
      if (gainedXP != 0) {
        Game.showNotification("You ${(gainedXP > 0 ? 'gained' : 'lost')} ${gainedXP} XP");
        Game.infoManager.addInfo(new XPInfo("${(gainedXP > 0 ? '+' : '-')} ${gainedXP} XP", player.x + 5, player.y - 15));
      }

      if (player.maxXP != maxXP) {
        player.maxXP = maxXP;
      }
    });

    this.on('Message.${Message.BLINK.index}', (data) {
      int id = data[1];

      if (!Game.entityIdExists(id)) {
        html.window.console.debug("Received BLINK message for an item that doesn't exist. (id=${id})");
        return;
      }

      Entity item = Game.getEntityByID(id);
      item.blink(150, () {});
    });

    this.on('Message.${Message.LEVEL.index}', (data) {
      var level = data[1];

      Game.player.level = level;
    });

    this.on('Message.${Message.DATA.index}', (data) {
      var dataObject = data[1];

      Game.player.loadFromObject(dataObject);
    });

    this.on('Message.${Message.INVENTORY.index}', (data) {
      var dataObject = data[1];

      Game.player.loadInventory(dataObject);
    });
  }

  void enable() {
    this.isListening = true;
  }

  void disable() {
    this.isListening = false;
  }

  void error(String message) {
    this.chat.insertError(message);
  }

  void notice(String message) {
    this.chat.insertNotice(message);
  }

  void connect([bool dispatcherMode = true]) {
    String url = "ws://${this.host}:${this.port}/";
    html.window.console.info("Trying to connect to server '${url}'");
    this.connection = new html.WebSocket(url);
    if (dispatcherMode) {
      this.connection.onMessage.listen((html.MessageEvent e) {
        var reply = JSON.decode(e.data);
        if (reply.status == "OK") {
          this.trigger("Dispatched", [reply.host, reply.port]);
        } else if (reply.status == "FULL") {
          html.window.alert("BrowserQuest is currently at maximum player population. Please retry later.");
        } else {
          html.window.alert("Unknown error while connecting to BrowserQuest.");
        }
      });
      return;
    }

    this.connection.onOpen.listen((html.Event event) {
      html.window.console.info("Connected to server ${this.host}:${this.port}");
    });

    this.connection.onMessage.listen((html.MessageEvent e) {
      if (e.data == "go") {
        this.trigger("Connected");
        return;
      }
      if (e.data == 'timeout') {
        this.isTimeout = true;
        return;
      }

      this.receiveMessage(e.data);
    });

    this.connection.onError.listen((html.ErrorEvent e) {
      html.window.console.error(e);
    });

    this.connection.onClose.listen((html.CloseEvent e) {
      html.window.console.debug("Connection closed");
      html.document.querySelector("#container").classes.add("error");

      if (this.isTimeout) {
        this.disconnected("You have been disconnected for being inactive for too long");
      } else {
        this.disconnected("The connection to BrowserQuest has been lost");
      }
    });
  }

  void sendMessage(dynamic data) {
    if (this.connection == null || this.connection.readyState != html.WebSocket.OPEN) {
      throw "Unable to send message - WebSocket is not connected.";
    }

    data[0] = data[0].index;
    var json = JSON.encode(data);
    this.connection.send(json);
    html.window.console.debug("dataOut: ${json}");
  }

  void receiveMessage(String message) {
    if (!this.isListening) {
      html.window.console.debug("Data received but client isn't listening yet");
      return;
    }

    var data = JSON.decode(message);
    html.window.console.debug("dataIn: ${message}");

    if (data[0] is List) {
      // Multiple actions received
      this.receiveActionBatch(data);
    } else {
      // Only one action received
      this.receiveAction(data);
    }
  }

  void receiveAction(data) {
    this.trigger('Message.${data[0]}', [data]);
  }

  void receiveActionBatch(actions) {
    actions.forEach((action) {
      this.receiveAction(action);
    });
  }

  void disconnected(String message) {
    if (Game.player != null) {
      Game.player.die();
    }

    Game.disconnected(message);
  }

  // TODO: uncomment
  /*void sendInventory(Inventory inventory) {*/
    /*this.sendMessage([Message.INVENTORY,*/
      /*inventory.serialize()*/
    /*]);*/
  /*}*/

  void sendInventoryItem(InventoryItem item) {
    this.sendMessage([Message.INVENTORYITEM,
        item.serialize()
    ]);
  }

  void sendInventorySwap(first, second) {
    this.sendMessage([Message.INVENTORYSWAP,
      first,
      second
    ]);
  }

  void sendUseItem(Item item, [Entity target = null]) {
    var message = [Message.USEITEM,
      item.id
    ];
    if (target != null) {
      message.add(target.id);
    }

    this.sendMessage(message);
  }

  void sendUseSpell(
    Spell spell,
    Entity target,
    Orientation orientation,
    int trackingId
  ) {
    var message = [Message.USESPELL,
      spell.kind
    ];

    var targetId = null;
    if (target != null) {
      targetId = target.id;
    }
    message.add(targetId);
    message.add(orientation);
    message.add(trackingId);

    this.sendMessage(message);
  }

  // TODO: uncomment
  /*void sendSkillbar(Skillbar skillbar) {*/
    /*this.sendMessage([Message.SKILLBAR,*/
      /*skillbar.serialize()*/
    /*]);*/
  /*}*/

  void sendThrowItem(Item item, [Entity target = null]) {
    List message = [Message.THROWITEM,
      item.id
    ];
    if (target != null) {
      message.add(target.id);
    }

    this.sendMessage(message);
  }

  void sendHello(String playerName, bool isResurrection) {
    this.sendMessage([Message.HELLO,
      playerName
    ]);
  }

  void sendResurrect() {
    this.sendMessage([Message.RESURRECT]);
  }

  void sendMove(Position position) {
    this.sendMessage([Message.MOVE,
      position.x,
      position.y
    ]);
  }

  void sendLootMove(Item item, Position position) {
    this.sendMessage([Message.LOOTMOVE,
      position.x,
      position.y,
      item.id
    ]);
  }

  void sendAggro(Mob mob) {
    this.sendMessage([Message.AGGRO,
      mob.id
    ]);
  }

  void sendAttack(Mob mob) {
    this.sendMessage([Message.ATTACK,
      mob.id
    ]);
  }

  void sendHit(Mob mob) {
    this.sendMessage([Message.HIT,
      mob.id
    ]);
  }

  void sendHurt(Character character) {
    this.sendMessage([Message.HURT,
      character.id
    ]);
  }

  void sendChat(String text, [String channel]) {
    if (channel == null) {
      channel = this.chat.channel;
    }
    this.sendMessage([Message.CHAT,
      text,
      channel
    ]);
  }

  void sendPartyAccept(int inviterId) {
    this.sendMessage([Message.PARTY_ACCEPT,
      inviterId
    ]);
  }

  void sendPartyLeaderChange(int playerID) {
    this.sendMessage([Message.PARTY_LEADER_CHANGE,
      playerID
    ]);
  }

  void sendPartyLeave() {
    this.sendMessage([Message.PARTY_LEAVE]);
  }

  void sendPartyInvite(int playerId) {
    this.sendMessage([Message.PARTY_INVITE,
      Game.player.id,
      playerId
    ]);
  }

  void sendPartyKick(int playerId) {
    this.sendMessage([Message.PARTY_KICK,
      playerId
    ]);
  }

  void sendGuildCreate(String name) {
    this.sendMessage([Message.GUILD_CREATE,
      name
    ]);
  }

  void sendGuildAccept(String name) {
    this.sendMessage([Message.GUILD_ACCEPT,
      name
    ]);
  }

  void sendGuildLeaderChange(String name) {
    this.sendMessage([Message.GUILD_LEADER_CHANGE,
      name
    ]);
  }

  void sendGuildQuit() {
    this.sendMessage([Message.GUILD_QUIT]);
  }

  void sendGuildInvite(String name) {
    this.sendMessage([Message.GUILD_INVITE,
      name
    ]);
  }

  void sendGuildKick(String name) {
    this.sendMessage([Message.GUILD_KICK,
      name
    ]);
  }

  void sendGuildOnline() {
    this.sendMessage([Message.GUILD_ONLINE]);
  }

  void sendGuildMembers() {
    this.sendMessage([Message.GUILD_MEMBERS]);
  }

  void sendLoot(Item item) {
    this.sendMessage([Message.LOOT,
      item.id
    ]);
  }

  void sendTeleport(Position position) {
    this.sendMessage([Message.TELEPORT,
      position.x,
      position.y
    ]);
  }

  void sendWho(List<int> ids) {
    List data = [Message.WHO];
    data.addAll(ids);
    this.sendMessage(data);
  }

  void sendZone() {
    this.sendMessage([Message.ZONE]);
  }

  void sendOpen(Chest chest) {
    this.sendMessage([Message.OPEN,
      chest.id
    ]);
  }

  void sendCheck(int id) {
    this.sendMessage([Message.CHECK,
      id
    ]);
  }

  void handlePlayerEnter(playerData) {
    Player player = Game.getPlayerByID(playerData['id']);
    if (player != null) {
      // already exists - skip it
      return;
    }

    player = EntityFactory.createEntity(Entities.get(playerData['kind']), playerData['id'], playerData['name']);
    player.loadFromObject(playerData['data']);
    Game.addPlayer(player);
  }
}