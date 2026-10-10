import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import '../runtime_world.dart';
import 'flame_object_components.dart';
import '../runtime_object_factory.dart';

/// Lazy-only physics engine (~3MB Forge2D). Do NOT instantiate directly —
/// gate via `RuntimePhysicsGate.shouldUsePhysics(world.profile)` first.
/// Non-physics profiles must use the Behavior/Effect math engine instead.
class ExperimentFlameGame extends Forge2DGame {
  final RuntimeWorld runtimeWorld;

  ExperimentFlameGame(this.runtimeWorld) : super(gravity: Vector2(0, 9.8));

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Create boundaries
    final boundaries = createBoundaries(this);
    addAll(boundaries);

    // Initialize objects from registry
    for (var objData in runtimeWorld.objects.allObjects) {
      final comp = RuntimeObjectFactory.create(objData, runtimeWorld);
      if (comp is PositionComponent) {
        comp.position = Vector2(size.x / 2, size.y / 2);
      }
      add(comp);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Sync the runtime world with the flame game loop
    runtimeWorld.tick(dt);

    // Update gravity if 'gravity' variable exists
    final g = runtimeWorld.variables.get('gravity');
    if (g is num) {
      world.physicsWorld.gravity = Vector2(0, g.toDouble());
    }
  }

  List<Component> createBoundaries(Forge2DGame game) {
    final topLeft = Vector2.zero();
    final bottomRight = game.size;
    final topRight = Vector2(bottomRight.x, topLeft.y);
    final bottomLeft = Vector2(topLeft.x, bottomRight.y);

    return [
      Wall(topLeft, topRight),
      Wall(topRight, bottomRight),
      Wall(bottomRight, bottomLeft),
      Wall(bottomLeft, topLeft),
    ];
  }
}

class Wall extends BodyComponent {
  final Vector2 start;
  final Vector2 end;

  Wall(this.start, this.end);

  @override
  Body createBody() {
    final shape = EdgeShape()..set(start, end);
    final fixtureDef = FixtureDef(shape, friction: 0.3);
    final bodyDef = BodyDef(
      position: Vector2.zero(),
      type: BodyType.static,
    );

    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }
}
