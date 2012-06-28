/*
    Copyright © 2011, 2012 MLstate

    This file is part of OPA.

    OPA is free software: you can redistribute it and/or modify it under the
    terms of the GNU Affero General Public License, version 3, as published by
    the Free Software Foundation.

    OPA is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public License for
    more details.

    You should have received a copy of the GNU Affero General Public License
    along with OPA.  If not, see <http://www.gnu.org/licenses/>.
*/

//////////////////////////////////////////////////////////////////////
// BEWARE THIS FILE IS SHARING BEETWEEN THE JAVASCRIPT AND NODE BSL //
//////////////////////////////////////////////////////////////////////


/**
   Bypasses for CPS

   @author Maxime Audouin <maxime.audouin@mlstate.com>
   @author Rudy Sicard
   @review David Rajchenbach-Teller (started Aug 20th, 2010)

   @author Quentin Bourgerie 2012
*/

##extern-type Cps.future('a)
##extern-type continuation('a)
##extern-type [normalize] func('a, 'b)
##extern-type [normalize] black_future

##extern-type [normalize] _unit_continuation
##extern-type [normalize] _unit
    /* the type unit that doesn't get projected */

##register debug \ cps_debug : int, string -> void


//////////////////////////////////////////////////
// BARRIER ///////////////////////////////////////
//////////////////////////////////////////////////
##register [opacapi, no-projection, restricted : cps] before_wait : -> void
##args()
{
  // Nothing todo
  return js_void;
}

/**
 * @param {(number|string)=} name An optional name, used for debugging purposes
 * @return {!Barrier}
 */
function make_barrier(name)
{
  return new Barrier(name);
}
##register [no-projection, restricted : cps] make_barrier       \ make_barrier    : string -> Cps.future('a)
##register [no-projection, restricted : cps] black_make_barrier \ make_barrier    : string -> black_future
//'

/**
 * Non-blocking wait for a barrier to be [release]d
 *
 * @param {!Barrier} barrier
 * @param {!Continuation} k
 * @return {!*}
 */
function wait_barrier(barrier, k){
  barrier.wait(k);
}
##register [no-projection, restricted : cps] wait \ wait_barrier : Cps.future('a), continuation('a) -> void


/**
 * Release a [Barrier]
 *
 * @param {!Barrier} barrier
 * @param {!*} x The value to release
 * @return {!*}
 */
function release_barrier(barrier, x){
  barrier.release(x);
}
##register [no-projection, restricted : cps] release_barrier \ release_barrier : Cps.future('a), 'a -> void

function toplevel_wait(barrier){
  return blocking_wait(barrier);
}
##register [opacapi, no-projection, restricted : cps] toplevel_wait \ toplevel_wait : Cps.future('a) -> 'a
##register [opacapi, no-projection, restricted : cps] black_toplevel_wait \ toplevel_wait : black_future -> 'a


//////////////////////////////////////////////////
// EXCEPTION /////////////////////////////////////
//////////////////////////////////////////////////
##register [opacapi, no-projection, restricted : cps] handler_cont \ `QmlCpsLib_handler_cont` : continuation('a) -> continuation('c)

##register [opacapi, no-projection : cps, restricted : cps] catch_native : \
(opa['c], continuation('a) -> _unit), continuation('a) -> continuation('a)
##args(h, k)
{
  return k.catch_(h);
}


##register [no-projection : cps, restricted : cps] spawn \ spawn : (_unit, continuation('a) -> _unit) -> Cps.future('a)

##register [opacapi, no-projection : cps, restricted : cps] callcc_directive \ `QmlCpsLib_callcc_directive` : (continuation('a), _unit_continuation -> _unit), continuation('a) -> _unit

##register [no-projection : cps] thread_context : continuation('a) -> option(opa['thread_context])
##args(b)
{
  var c = b._context;
  return c ? js_some(c) : js_none;
}

##register [no-projection, restricted : cps] with_thread_context : opa['b], continuation('a) -> continuation('a)
##args(tc, b)
{
  return new Continuation(b._payload, tc, b._options);
}


##register [no-projection:cps, restricted:cps] cont_native \ `cont` : ('a -> _unit) -> continuation('a)
function cont(f){
  return new Continuation(f);
}

##register [no-projection:cps, restricted:cps] ccont_native \ `ccont` : continuation('b), ('a -> _unit) -> continuation('a)
function ccont(b, f){
  return new Continuation(f, b._context, b._options);
}

##register [no-projection, restricted : cps] return \ return_ : continuation('a), 'a -> void

##register [no-projection, restricted : cps] black_release_barrier \ release_barrier : black_future, 'a -> void

##register [no-projection, restricted : cps] loop_schedule \ loop_schedule : opa['d] -> void

##register user_return \ return_ : continuation('a), 'a -> void


##register user_cont : ('a -> void) -> continuation('a)
##args(f)
{
  return cont(f);
}

##register execute : continuation('a), 'a -> void
##args(k, x)
{
  execute(k, x);
  return js_void;
}

/**
 * The thread context for this VM
 */
#<Ifstatic:OPABSL_NODE>
  var global_thread_context = js_none
#<Else>
var global_cookie = getStableCookie();
global_cookie = ('some' in global_cookie)?global_cookie.some:"BADCOOKIE";
var global_thread_context =
  js_some(normalize_obj(
  {
      key:{
          client:{
              client: global_cookie,
              page  : page_server
          }},
      request: js_none,
      details:{
          some:{
              locale:  js2list([window.navigator.language]),
              browser: {
                  environment: { Unidentified: js_void },
                  renderer:    { Unidentified: js_void }
              }
          }
      },
      constraint: {free:js_void}
  }
  ));
#<End>

##module Notcps_compatibility
  ##register [opacapi] thread_context : opa['d] -> option(opa['b])
    ##args(a)
    {
        return global_thread_context;
    }

  ##register with_thread_context : opa['d], 'a -> 'a
    ##args(a, b)
    {
      return b;
    }

##endmodule

##register print_trace : continuation(_) -> void
##args(_)
{
    console.log("BslCps.print_trace", "NYI");
    return ;
}
