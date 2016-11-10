# -*- coding: utf-8 -*-
"""
@author: mieszko.zielinski
"""

import copy
from contextlib import contextmanager


class Task(object):
    """ Here only to have a conceptual hierarchy. """
    def __init__(self, task_name):
        self.name = task_name


class CompoundTask(Task):
    """ A task that gets decomposed into other tasks """
    def __init__(self, task_name):
        super(CompoundTask, self).__init__(task_name)
        self._methods = []

    @contextmanager
    def add_method(self, condition=None):
        new_method = Method(condition)
        self._methods.append(new_method)
        yield new_method

    def methods(self):
        return self._methods

    def find_satisfied_method(self, world_state, start_index=0):
        # iterate through all methods and return the first one
        # which conditions are met
        # @todo need to hangle re-runs starting with following methods
        for i in range(start_index, len(self._methods)):
            method = self._methods[i]
            if world_state.check(method.conditions()):
                return method, i

        return None, -1


class Method(object):
    """ A way to decompose owner CompoundTasks into other tasks """
    def __init__(self, conditions=None):
        self._subtasks = []
        self._conditions = conditions

    def add_task(self, task):
        self._subtasks.append(task)

    def conditions(self):
        return self._conditions

    def subtasks(self):
        return self._subtasks


class PrimitiveTask(Task):
    """ A task that cannot be decomposed any further. The actual
        action to be performed is expressed as an Operator and its
        parameters. """
    def __init__(self, task_name):
        super(PrimitiveTask, self).__init__(task_name)
        self.operator = None
        self.effects = []
        self._conditions = []

    def check_condition(self, world_state):
        return world_state.check(self._conditions)

    def conditions(self):
        return self._conditions

    def set_conditions(self, conditions):
        self._conditions = conditions


class Domain(object):
    """ A set if possible tasks, some of which can be decomposed
        into other tasks. """
    def __init__(self):
        self._tasks = {}

    def add_task(self, task):
        if task.name in self._tasks.keys():
            print('Warning: overriding %s with a new task' % task.name)
        self._tasks[task.name] = task
        return task

    def find_task(self, task_name):
        return self._tasks[task_name]

    def tasks(self):
        return self._tasks

    def _compile_compound(self, task):
        """ worker function called by 'compile' function """
        methods = task.methods()
        if len(methods) == 0:
            print('Compound task %s has no methods' % task.name)
        else:
            for method in methods:
                for subtask_name in method.subtasks():
                    # check if the task is in the domain, and if not, complain
                    if subtask_name not in self._tasks.keys():
                        print('Task %s is using undefined task %s' % (task.name, subtask_name))

    def compile(self):
        """ main entry point for domain validation. It mostly checks if all
            PrimitiveTasks used by CompositeTasks are defined as well """
        for task in self._tasks.values():
            #print('Processing ' + task.name)
            if isinstance(task, CompoundTask):
                self._compile_compound(task)
            else:
                # could add a check if primitive task is set up properly
                pass

    def __repr__(self):
        """ nice print out of the domain """
        result = ''
        for task in self._tasks.values():
            result += '- %s\n' % task.name
            if isinstance(task, CompoundTask):
                for method in task.methods():
                    result += '--- %s\n' % str(method.conditions())
                    for subtask in method.subtasks():
                        result += '------ %s\n' % subtask
        return result


class WorldState(object):
    """ What we know about the world """
    def __init__(self, domain=None):
        # key-value representation of world knowledge
        self._knowledge = {}
        # operation look-up
        self._ops = {}
        self._ops['=='] = lambda a, b: a == b
        self._ops['='] = lambda a, b: b
        self._ops['>'] = lambda a, b: a > b
        self._ops['+='] = lambda a, b: a + b

        if domain:
            # a if domain has been passed in we can use it to
            # seed the world state knowledge dictionary with
            # expected keys """
            for task in domain.tasks().values():
                if isinstance(task, CompoundTask):
                    for method in task.methods():
                        if method.conditions() is not None:
                            for wskey, _, _ in method.conditions():
                                self._knowledge[wskey] = None
                else:
                    for wskey, _, _ in task.conditions():
                        self._knowledge[wskey] = None
                    for wskey, _, _ in task.effects:
                        self._knowledge[wskey] = None

    def get_copy(self):
        """ Needed due to python's (efficiency-driven) tendency
            to shallow-copy eveything """
        new_ws = WorldState()
        new_ws._knowledge = copy.deepcopy(self._knowledge)
        new_ws._ops = self._ops
        return new_ws

    def check(self, condition):
        """ tests given 'condition' agains stored facts """
        if condition is None:
            return True
        elif not isinstance(condition, list):
            key, operation, argument = condition
            if key in self._knowledge.keys() and operation in self._ops.keys():
                return self._ops[operation](self._knowledge[key], argument)
            else:
                return False
        else:
            for item in condition:
                if not self.check(item):
                    return False
            return True

    def apply(self, effect):
        """ applies given 'effect' to the stored world knowledge """
        if not isinstance(effect, list):
            key, operation, argument = effect
            if key in self._knowledge.keys() and operation in self._ops.keys():
                self._knowledge[key] = self._ops[operation](self._knowledge[key], argument)
        else:
            for item in effect:
                self.apply(item)

    def __getitem__(self, key):
        """ for the list-like reading """
        return self._knowledge[key]

    def __setitem__(self, key, value):
        """ for the list-like assigning """
        self._knowledge[key] = value

    def __repr__(self):
        """ for nicer printing """
        return str(self._knowledge)


class HTNPlanner(object):
    """ the planner implementation, finding a "path" through
        Domain at given the WorldState """
    def __init__(self, domain, world_state):
        self._domain = domain
        self._start_world_state = world_state
        self.__rollback_stack = []

    def record_decomposition(self, current_task, method_index, working_ws, final_plan):
        """ stored given planning state so that it can be
            restored if need be """
        self.__rollback_stack.append((current_task, method_index, working_ws.get_copy()\
                                    , copy.deepcopy(final_plan)))

    def restore_last_decomposition(self):
        """ restored rollback point stored with a
            call to 'record_decomposition' """
        return self.__rollback_stack.pop()

    def generate_plan(self, task_name):
        """ where the planning magic happens """
        final_plan = []
        self.__rollback_stack = []
        working_ws = self._start_world_state
        tasks_to_process = [task_name]
        while len(tasks_to_process) > 0:

            self.print_progress(final_plan, tasks_to_process)

            current_task_name = tasks_to_process.pop()
            current_task = self._domain.find_task(current_task_name)
            next_method = 0

            if isinstance(current_task, CompoundTask):
                satisfied_method, method_index\
                    = current_task.find_satisfied_method(working_ws, next_method)
                if satisfied_method is not None:
                    self.record_decomposition(current_task, method_index, working_ws, final_plan)

                    tmp_tasks = copy.deepcopy(satisfied_method.subtasks())
                    tmp_tasks.reverse()

                    tasks_to_process.extend(tmp_tasks)

                else:
                    current_task, next_method, working_ws, final_plan\
                                            = self.restore_last_decomposition()
                    tasks_to_process.append(current_task.name)

            else: # PrimitiveTask
                if current_task.check_condition(working_ws):
                    working_ws.apply(current_task.effects)
                    final_plan.append(current_task_name)
                else:
                    current_task, next_method, working_ws, final_plan\
                                            = self.restore_last_decomposition()
                    tasks_to_process.append(current_task.name)

        return final_plan

    def print_progress(self, final_plan, tasks_to_process):
        print(final_plan, end=' ')
        tasks_to_process_print = copy.deepcopy(tasks_to_process)
        tasks_to_process_print.reverse()
        print(tasks_to_process_print)


@contextmanager
def compound_task(domain, task_name):
    task = domain.add_task(CompoundTask(task_name))
    yield task

@contextmanager
def primitive_task(domain, task_name, conditions=None):
    task = domain.add_task(PrimitiveTask(task_name))
    if conditions is not None:
        task.set_conditions(conditions)
    yield task


def __test():

    domain = Domain()
    with compound_task(domain, 'Root') as ct:
        with ct.add_method([('WsEnemyHealth', '>', 0)]) as method:
            method.add_task('AttackEnemy')
        with ct.add_method() as method:
            method.add_task('FindPatrolPoint')
            method.add_task('NavigateToPatrolPoint')

    with compound_task(domain, 'AttackEnemy') as ct:
        with ct.add_method([('WsHasWeapon', '==', True)]) as method:
            method.add_task('NavigateToEnemy')
            method.add_task('UseWeapon')
            method.add_task('Root')
        with ct.add_method() as method:
            method.add_task('FindWeapon')
            method.add_task('NavigateToWeapon')
            method.add_task('PickUpWeapon')
            method.add_task('AttackEnemy')

    with primitive_task(domain, 'FindPatrolPoint') as pt:
        pt.operator = ['OpFindPatrolPoint', 'VarPatrolPoint']
        pt.effects = [('WsHasPatrolPoint', '=', True)]

    with primitive_task(domain, 'FindWeapon') as pt:
        pt.operator = ['OpFindWeapon', 'VarWeapon', 'VarWeaponPickUp']

    with primitive_task(domain, 'NavigateToPatrolPoint') as pt:
        pt.operator = ['OpNavigateTo', 'VarPatrolPoint']
        pt.effects = [('WsLocation', '=', 'VarPatrolPoint')]

    with primitive_task(domain, 'NavigateToEnemy') as pt:
        pt.operator = ['OpNavigateTo', 'WsEnemy']
        pt.effects = [('WsLocation', '=', 'WsEnemy'), ('WsCanSeeEnemy', '=', True)]

    with primitive_task(domain, 'NavigateToWeapon') as pt:
        pt.operator = ['OpNavigateTo', 'VarWeaponPickUp']
        pt.effects = [('WsLocation', '=', 'VarWeaponPickUp')]

    with primitive_task(domain, 'PickUpWeapon') as pt:
        pt.operator = ['OpPickUp', 'VarWeapon']
        pt.effects = [('WsHasWeapon', '=', True)]

    with primitive_task(domain, 'UseWeapon') as pt:
        pt.operator = ['OpUseWeapon', 'WsEnemy']
        pt.effects = [('WsAmmo', '+=', -1), ('WsEnemyHealth', '+=', -1)]

    # validate the constructed domain
    domain.compile()

    # create world state seeding it with entries required by domain
    world_state = WorldState(domain)
    world_state['WsAmmo'] = 3
    world_state['WsEnemyHealth'] = 2

    planner = HTNPlanner(domain, world_state)

    print("Planning in progress:")
    plan = planner.generate_plan('Root')

    print("Final plan:")
    for action in plan:
        print("\t" + action)

    print('done.')

if __name__ == '__main__':
    __test()
