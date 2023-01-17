import numpy
import jax
import jax._src.lax_reference as lax_reference
from jax import core
from jax._src.util import safe_map
import flax
from neurallogic import symbolic_primitives
from plum import dispatch
import typing
from typing import (Any, Mapping)

# TODO: rename this file to symbolic.py


def symbolic_bind(prim, *args, **params):
    # print("\nprimitive: ", prim.name)
    # print("args: ", args)
    # print("params: ", params)
    symbolic_outvals = {
        'broadcast_in_dim': symbolic_primitives.symbolic_broadcast_in_dim,
        'reshape': lax_reference.reshape,
        'convert_element_type': symbolic_primitives.symbolic_convert_element_type,
        'and': symbolic_primitives.symbolic_and,
        'or': symbolic_primitives.symbolic_or,
        'xor': symbolic_primitives.symbolic_xor,
        'not': symbolic_primitives.symbolic_not,
        'ne': symbolic_primitives.symbolic_ne,
        'gt': symbolic_primitives.symbolic_gt,
        'reduce_and': symbolic_primitives.symbolic_reduce_and,
        'reduce_or': symbolic_primitives.symbolic_reduce_or,
        'reduce_sum': symbolic_primitives.symbolic_reduce_sum,
    }[prim.name](*args, **params)
    return symbolic_outvals

def scope_put_variable(self, col: str, name: str, value: Any):
    variables = self._collection(col)

    def put(target, key, val):
        if (key in target and isinstance(target[key], dict) and
                isinstance(val, Mapping)):
            for k, v in val.items():
                put(target[key], k, v)
        else:
            target[key] = val

    put(variables, name, value)


def put_variable(self, col: str, name: str, value: Any):
    self.scope._variables = self.scope.variables().unfreeze()
    scope_put_variable(self.scope, col, name, value)

def make_symbolic_flax_jaxpr(flax_layer, x):
    actual_weights = flax_layer.get_variable("params", "weights")
    # Convert actual weights to dummy numeric weights (if needed)
    if isinstance(actual_weights, list) or (isinstance(actual_weights, numpy.ndarray) and actual_weights.dtype == object):
        numeric_weights = symbolic_primitives.map_at_elements(actual_weights, lambda x: 0)
        numeric_weights = numpy.asarray(numeric_weights, dtype=numpy.int32)
        put_variable(flax_layer, "params", "weights", numeric_weights)
    # Convert input to dummy numeric input (if needed)
    if isinstance(x, list) or (isinstance(x, numpy.ndarray) and x.dtype == object):
        x = symbolic_primitives.map_at_elements(x, lambda x: 0)
        x = numpy.asarray(x, dtype=numpy.int32)
    # Make the jaxpr that corresponds to the flax layer
    jaxpr = make_symbolic_jaxpr(flax_layer, x)
    # Replace the dummy numeric weights with the actual weights in the jaxpr
    jaxpr.consts = [actual_weights]
    return jaxpr


def eval_jaxpr(symbolic, jaxpr, consts, *args):
    """Evaluates a jaxpr by interpreting it as Python code.

    Parameters
    ----------
    symbolic : bool
        Whether to return symbolic values or concrete values. If symbolic is
        True, returns symbolic values, and if symbolic is False, returns
        concrete values.
    jaxpr : Jaxpr
        The jaxpr to interpret.
    consts : tuple
        Constant values for the jaxpr.
    args : tuple
        Arguments for the jaxpr.

    Returns
    -------
    out : tuple
        The result of evaluating the jaxpr.
    """

    # Mapping from variable -> value
    env = {}
    symbolic_env = {}

    # TODO: unify read and symbolic_read

    def read(var):
        # Literals are values baked into the Jaxpr
        if type(var) is core.Literal:
            return var.val
        return env[var]

    def symbolic_read(var):
        # Literals are values baked into the Jaxpr
        if type(var) is core.Literal:
            return var.val
        return symbolic_env[var]

    def write(var, val):
        env[var] = val

    def symbolic_write(var, val):
        symbolic_env[var] = val

    # Bind args and consts to environment
    if not symbolic:
        safe_map(write, jaxpr.invars, args)
        safe_map(write, jaxpr.constvars, consts)
    safe_map(symbolic_write, jaxpr.invars, args)
    safe_map(symbolic_write, jaxpr.constvars, consts)

    def eval_jaxpr_impl(jaxpr):
        # Loop through equations and evaluate primitives using `bind`
        for eqn in jaxpr.eqns:
            # Read inputs to equation from environment
            if not symbolic:
                invals = safe_map(read, eqn.invars)
            symbolic_invals = safe_map(symbolic_read, eqn.invars)
            prim = eqn.primitive
            if type(prim) is jax.core.CallPrimitive:
                call_jaxpr = eqn.params['call_jaxpr']
                if not symbolic:
                    safe_map(write, call_jaxpr.invars, map(read, eqn.invars))
                try:
                    safe_map(symbolic_write, call_jaxpr.invars,
                             map(symbolic_read, eqn.invars))
                except:
                    pass
                eval_jaxpr_impl(call_jaxpr)
                if not symbolic:
                    safe_map(write, eqn.outvars, map(read, call_jaxpr.outvars))
                safe_map(symbolic_write, eqn.outvars, map(
                    symbolic_read, call_jaxpr.outvars))
            else:
                if not symbolic:
                    outvals = prim.bind(*invals, **eqn.params)
                symbolic_outvals = symbolic_bind(
                    prim, *symbolic_invals, **eqn.params)
                # Primitives may return multiple outputs or not
                if not prim.multiple_results:
                    if not symbolic:
                        outvals = [outvals]
                    symbolic_outvals = [symbolic_outvals]
                if not symbolic:
                    # Check that the concrete and symbolic values are equal
                    assert numpy.array_equal(
                        numpy.array(outvals), symbolic_outvals)
                # Write the results of the primitive into the environment
                if not symbolic:
                    safe_map(write, eqn.outvars, outvals)
                safe_map(symbolic_write, eqn.outvars, symbolic_outvals)

    # Read the final result of the Jaxpr from the environment
    eval_jaxpr_impl(jaxpr)
    if not symbolic:
        return safe_map(read, jaxpr.outvars)[0]
    else:
        return safe_map(symbolic_read, jaxpr.outvars)[0]

# TODO: parameterise these functions by the element conversion function

# TODO: use union types to consolidate these functions
@dispatch
def make_symbolic(x: dict):
    return symbolic_primitives.map_at_elements(x, symbolic_primitives.to_boolean_value_string)

@dispatch
def make_symbolic(x: list):
    return symbolic_primitives.map_at_elements(x, symbolic_primitives.to_boolean_value_string)

@dispatch
def make_symbolic(x: numpy.ndarray):
    return symbolic_primitives.map_at_elements(x, symbolic_primitives.to_boolean_value_string)

@dispatch
def make_symbolic(x: jax.numpy.ndarray):
    return symbolic_primitives.map_at_elements(convert_jax_to_numpy_arrays(x), symbolic_primitives.to_boolean_value_string)


@dispatch
def make_symbolic(x: bool):
    return symbolic_primitives.to_boolean_value_string(x)


@dispatch
def make_symbolic(x: str):
    return symbolic_primitives.to_boolean_value_string(x)


@dispatch
def convert_jax_to_numpy_arrays(x: jax.numpy.ndarray):
    return numpy.asarray(x)


@dispatch
def convert_jax_to_numpy_arrays(x: dict):
    return {k: convert_jax_to_numpy_arrays(v) for k, v in x.items()}


@dispatch
def make_symbolic(x: flax.core.FrozenDict):
    x = convert_jax_to_numpy_arrays(x.unfreeze())
    return flax.core.FrozenDict(make_symbolic(x))

@dispatch
def make_symbolic(*args):
    return tuple([make_symbolic(arg) for arg in args])

@dispatch
def make_symbolic_jaxpr(func: typing.Callable, *args):
    return jax.make_jaxpr(lambda *args: func(*args))(*args)


def eval_symbolic(symbolic_function, *args):
    if hasattr(symbolic_function, 'literals'):
        return eval_jaxpr(False, symbolic_function.jaxpr, symbolic_function.literals, *args)
    return eval_jaxpr(False, symbolic_function.jaxpr, [], *args)


def symbolic_expression(jaxpr, *args):
    if hasattr(jaxpr, 'literals'):
        sym_expr = eval_jaxpr(True, jaxpr.jaxpr,
                              jaxpr.literals, *args)
    else:
        sym_expr = eval_jaxpr(True, jaxpr.jaxpr, [], *args)
    return sym_expr


@dispatch
def eval_symbolic_expression(x: str):
    return eval(x)


@dispatch
def eval_symbolic_expression(x: numpy.ndarray):
    return numpy.vectorize(eval)(x)


@dispatch
def eval_symbolic_expression(x: list):
    return numpy.vectorize(eval)(x)
