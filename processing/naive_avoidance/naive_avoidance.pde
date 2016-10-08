int creatureLimit = 80;
int initialPopulationSize = 10;
int activecreaturecount = 0;
float predatorChance = 0.0;
float maxCreatureSize = 20.0;
float initialSize = 10.0;
int drawTransparency = 64;
float turnSpeed = 0.07;
Creature[] neighbourCache = new Creature[creatureLimit + 1];
Creature[] creatures;
Predator[] predators;
Pray[] pray;
int predatorcount = 0;
int praycount = 0;
CreatureLookup lookupMap;
SmartOne smartOne;
Creature mouseCreature;

float sgn(float InValue)
{
  return InValue >= 0 ? 1.0 : -1.0;
}

class MapCell
{
  Creature[] cellElements;
  int creaturecount;

  MapCell()
  {
    // +1 to use last null as a stop sign
    cellElements = new Creature[creatureLimit + 1];
    creaturecount = 0;
  }

  void reset()
  {
    creaturecount = 0;
  }

  void add(Creature inCreature)
  {
    cellElements[creaturecount++] = inCreature;
    cellElements[creaturecount] = null;
  }
}

class CreatureLookup
{
  MapCell[] cells;
  float lookupCellSize;
  int columncount;
  int rowcount;

  CreatureLookup()
  {
    lookupCellSize = 100.0;
    columncount = ceil(width / lookupCellSize);
    rowcount = ceil(height / lookupCellSize);
    print("columncount " + columncount + " rowcount " + rowcount);
    cells = new MapCell[columncount * rowcount];
    for (int cellIndex = 0; cellIndex < cells.length; cellIndex++)
    {
      cells[cellIndex] = new MapCell();
    }
  }

  void reset()
  {
    for (int cellIndex = 0; cellIndex < cells.length; cellIndex++)
    {
      cells[cellIndex].reset();
    }
  }

  void add(Creature InCreature)
  {
    int row = int(InCreature.posY / lookupCellSize);
    int column = int(InCreature.posX / lookupCellSize);
    int cellIndex = row * columncount + column;
	if (cellIndex >= 0 && cellIndex < cells.length)
    {
		cells[cellIndex].add(InCreature);		
	}
  }

  int getCreaturesInRadius(float inX, float inY, float InRadius, Creature[] outCreatures)
  {
    outCreatures[0] = null;

    int count = 0;
    // extend the radius to catch creatures in neigbouring cells
    // we assume lookupCellSize > maxCreatureSize
    float cellRadius = InRadius + lookupCellSize;

    int startX = max(floor((inX - cellRadius) / lookupCellSize), 0);
    int endX = min(ceil((inX + cellRadius) / lookupCellSize), columncount - 1);
    int startY = max(floor((inY - cellRadius) / lookupCellSize), 0);
    int endY = min(ceil((inY + cellRadius) / lookupCellSize), rowcount - 1);

    for (int rowIndex = startY; rowIndex <= endY; rowIndex++)
    {
      int FirstcolumnIndex = rowIndex * columncount;
      for (int columnIndex = startX; columnIndex <= endX; columnIndex++)
      {
        MapCell Cell = cells[FirstcolumnIndex + columnIndex];
        int creatureIndex = 0;
        Creature creature = Cell.cellElements[creatureIndex];
        while (creature != null)
        {
          if (dist(inX, inY, creature.posX, creature.posY) < InRadius + creature.size / 2)
          {
            outCreatures[count] = Cell.cellElements[creatureIndex];
            count++;
            outCreatures[count] = null;
          }
          creatureIndex++;
          creature = Cell.cellElements[creatureIndex];
        }
      }
    }

    return count;
  }
}

class Creature
{
  int creatureIndex;
  float posX, posY;
  float velX, velY;
  float size;

  Creature(float inX, float inY)
  {
    creatureIndex = 0;
    posX = inX;
    posY = inY;
    velX = random(2.0) - 1.0;
    velY = random(2.0) - 1.0;
    size = initialSize;
  }

  void update()
  {
    if (posX + velX + size >= width)
    {
      velX = -1.0;
    }
    else if (posX + velX - size <= 0)
    {
      velX = 1.0;
    }

    if (posY + velY + size >= height)
    {
      velY = -1.0;
    }
    else if (posY + velY - size <= 0)
    {
      velY = 1.0;
    }

    posX += velX;
    posY += velY;
  }

  void draw()
  {
    ellipse(posX, posY, size * 2, size * 2);
  }
}

class Predator extends Creature
{
  Predator(float inX, float inY)
  {
    super(inX, inY);
  }

  void update()
  {
    if (size < maxCreatureSize && random(1.0) < 0.01)
    {
      size += 0.1;
    }
    super.update();
  }
}

class Pray extends Creature
{
  Pray(float inX, float inY)
  {
    super(inX, inY);
  }
}

class SmartOne extends Pray
{
  boolean bDrawDebug;
  boolean bAvoidBounds = false;
  float searchRadius;
  float desiredVelX;
  float desiredVelY;

  SmartOne(float inX, float inY)
  {
    super(inX, inY);
    bDrawDebug = false;
    searchRadius = 70;
    desiredVelX = 0;
    desiredVelY = 0;
  }

  void update()
  {
    lookupMap.getCreaturesInRadius(posX, posY, searchRadius, neighbourCache);

    int counter = 0;
    float weight = 0;
    float weightedX = 0;
    float weightedY = 0;
    while (neighbourCache[counter] != null && counter < neighbourCache.length)
    {
      Creature c = neighbourCache[counter++];
      if (c != this)
      {
        weight = 1.0 / ((c.posX - posX)*(c.posX - posX) + (c.posY - posY)*(c.posY - posY) + 0.1);// , c.posY, posX, posY);
        weightedX += (posX - c.posX) * weight;
        weightedY += (posY - c.posY) * weight;
      }
    }

    if (bAvoidBounds)
    {
      if (posX - searchRadius < 0)
      {
        counter++;
        weight = 1.0 / posX;
        weightedX += posX * weight* weight;
      }
      else if (posX + searchRadius > width)
      {
        counter++;
        weight = 1 / (width - posX);
        weightedX += -posX * weight* weight;
        //weightedY += posY * weight;
      }
      if (posY - searchRadius < 0)
      {
        counter++;
        weight = 1.0 / posY;
        weightedY += posY * weight* weight;
      }
      else if (posY + searchRadius > height)
      {
        counter++;
        weight = 1 / (height - posY);
        weightedY += -posY * weight* weight;
      }
    }

    if (counter > 0)
    {
      float newVelX = weightedX;
      float newVelY = weightedY;
      float length = sqrt(newVelX * newVelX + newVelY * newVelY);

      if (length > 0.001)
      {
        newVelX /= length;
        newVelY /= length;

        desiredVelX = newVelX;
        desiredVelY = newVelY;

        length = sqrt(velX * velX + velY * velY);
        velX /= length;
        velY /= length;

        float dot = velX * newVelX + velY * newVelY;
        // this is dumb, but neede to avoid NaNs
        if (dot > 1.0) dot = 1.0;
        if (dot < -1.0) dot = -1.0;

        float product = velX * newVelY - velY * newVelX;
        float angle = acos(dot) * sgn(product) * turnSpeed;
        newVelX = cos(angle) * velX - sin(angle) * velY;
        newVelY = sin(angle) * velX + cos(angle) * velY;

        velX = newVelX;
        velY = newVelY;
      }
      else
      {
        desiredVelX = velX;
        desiredVelY = velY;
      }
    }
	else
	{
		desiredVelX = desiredVelY = 0;
	}

    super.update();

    if (bDrawDebug)
    {
      drawDebug();
    }
  }

  void drawDebug()
  {
    int counter = 0;
    stroke(166, 166, 166, drawTransparency);

    while (neighbourCache[counter] != null && counter < neighbourCache.length)
    {
      Creature c = neighbourCache[counter++];
      line(c.posX, c.posY, posX, posY);
    }

    if (posX - searchRadius < 0)
    {
      line(0, posY, posX, posY);
    }
    else if (posX + searchRadius > width)
    {
      line(width, posY, posX, posY);
    }
    if (posY - searchRadius < 0)
    {
      line(posX, 0, posX, posY);
    }
    else if (posY + searchRadius > height)
    {
      line(posX, height, posX, posY);
    }

	if (desiredVelX != desiredVelY || desiredVelX != 0)
    {
		stroke(222, 0, 0, drawTransparency);
		line(posX, posY, posX + desiredVelX * 40, posY + desiredVelY * 40);
	}
  }

  void draw()
  {
    super.draw();
    if (bDrawDebug)
    {
      fill(22, 22, 22, 22);
      ellipse(posX, posY, searchRadius * 2, searchRadius * 2);
    }
  }
}

void setup()
{
  size(600, 600);
  mouseCreature = new Creature(mouseX, mouseY);
  mouseCreature.size = 5.0;
  lookupMap = new CreatureLookup();
  creatures = new Creature[creatureLimit];
  predators = new Predator[creatureLimit];
  pray = new Pray[creatureLimit];
  for (int Index = 0; Index < initialPopulationSize; Index++)
  {
    Creature creature = null;
    if (random(1.0) < predatorChance)
    {
      Predator predator = new Predator(random(initialSize, width - initialSize), random(initialSize, height - initialSize));
      predators[predatorcount] = predator;
      creature = predator;
      predatorcount++;
    }
    else
    {
      Pray newPray = new SmartOne(random(initialSize, width - initialSize), random(initialSize, height - initialSize));
      pray[praycount] = newPray;
      creature = newPray;
      praycount++;
    }
    creatures[Index] = creature;
    creature.creatureIndex = Index;
    activecreaturecount++;
  }

  smartOne = new SmartOne(random(initialSize, width - initialSize), random(initialSize, height - initialSize));
  smartOne.bDrawDebug = true;
  smartOne.searchRadius = 100;
  smartOne.bAvoidBounds = true;
}

void draw()
{
  background(255);
  mouseCreature.posX = mouseX;
  mouseCreature.posY = mouseY;

  lookupMap.reset();
  lookupMap.add(mouseCreature);

  for (int Index = 0; Index < activecreaturecount; Index++)
  {
    creatures[Index].update();
    lookupMap.add(creatures[Index]);
  }
  smartOne.update();

  noStroke();
  fill(204, 0, 0, drawTransparency);
  for (int Index = 0; Index < creatures.length; Index++)
  {
    if (pray[Index] == null)
    {
      break;
    }
    pray[Index].draw();
  }

  fill(0, 0, 204, drawTransparency);
  for (int Index = 0; Index < creatures.length; Index++)
  {
    if (predators[Index] == null)
    {
      break;
    }
    predators[Index].draw();
  }

  fill(0, 204, 0, drawTransparency);
  smartOne.draw();

  fill(0, 0, 200, drawTransparency);
  mouseCreature.draw();

  stroke(0, 0, 0, drawTransparency);
  for (int Index = 0; Index < activecreaturecount; Index++)
  {
    Creature creature = creatures[Index];
    line(creature.posX, creature.posY, creature.posX + creature.velX * creature.size * 1.1, creature.posY + creature.velY * creature.size * 1.1);
  }
  line(smartOne.posX, smartOne.posY, smartOne.posX + smartOne.velX * smartOne.size * 1.1, smartOne.posY + smartOne.velY * smartOne.size * 1.1);
}

void mouseReleased()
{
  if (activecreaturecount >= creatures.length)
  {
    return;
  }

  int SpawnX = mouseX;
  int SpawnY = mouseY;
  Pray newPray = new SmartOne(SpawnX, SpawnY);
  pray[praycount++] = newPray;
  creatures[activecreaturecount++] = newPray;
}
