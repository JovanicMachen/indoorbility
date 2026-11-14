"""Validate the supplied fictional graph; not a replacement for iOS tests."""
import heapq
import json
import math
from pathlib import Path


def validate(data):
    assert data['schema_version'] == 1
    for group in ('floors', 'nodes', 'edges'):
        ids = [item['id'] for item in data[group]]
        assert len(ids) == len(set(ids)), f'Duplicate {group} IDs'
    floors = {f['id'] for f in data['floors']}
    nodes = {n['id'] for n in data['nodes']}
    for node in data['nodes']:
        assert node['floor'] in floors
        assert all(math.isfinite(node[k]) for k in ('x', 'y'))
    for edge in data['edges']:
        assert edge['from'] in nodes and edge['to'] in nodes
        assert math.isfinite(edge['distance']) and edge['distance'] > 0
        assert edge['kind'] in ('hallway', 'elevator', 'stairs')
        assert type(edge['verified']) is bool and type(edge['blocked']) is bool


def route(data, blocked=frozenset(), avoid_stairs=True, start='entrance', goal='room_204'):
    adjacency = {n['id']: [] for n in data['nodes']}
    if start not in adjacency or goal not in adjacency:
        raise ValueError('Unknown checkpoint')
    for edge in data['edges']:
        if edge['blocked'] or not edge['verified'] or edge['id'] in blocked:
            continue
        if avoid_stairs and edge['kind'] == 'stairs':
            continue
        a, b = edge['from'], edge['to']
        adjacency[a].append((b, edge))
        adjacency[b].append((a, edge))
    queue = [(0, start, ())]
    best = {start: 0}
    while queue:
        cost, node, path = heapq.heappop(queue)
        if cost != best[node]:
            continue
        if node == goal:
            return cost, path
        for neighbor, edge in sorted(adjacency[node], key=lambda pair: pair[1]['id']):
            next_cost = cost + edge['distance']
            if next_cost < best.get(neighbor, math.inf):
                best[neighbor] = next_cost
                heapq.heappush(queue, (next_cost, neighbor, path + (edge['id'],)))
    return None


if __name__ == '__main__':
    data = json.loads(Path(__file__).with_name('demo_building.json').read_text())
    validate(data)
    initial = route(data)
    assert initial[0] == 39 and 'lift_a' in initial[1]
    alternative = route(data, {'lift_a'})
    assert alternative[0] == 47 and 'lift_b' in alternative[1]
    assert route(data, {'lift_a', 'lift_b'}) is None
    stairs = route(data, avoid_stairs=False)
    assert stairs[0] == 33 and 'stair_connector' in stairs[1]
    assert route(data, start='room_204', goal='entrance')[0] == 39
    assert route(data, start='entrance', goal='entrance') == (0, ())
    try:
        route(data, start='missing')
        raise AssertionError('Unknown start was accepted')
    except ValueError:
        pass
    for edge in data['edges']:
        if edge['id'] == 'lift_a':
            edge['verified'] = False
    assert route(data)[0] == 47
    print('PASS: graph validation and 8 route scenarios. Costs: Lift A 39, Lift B 47, stairs 33.')
