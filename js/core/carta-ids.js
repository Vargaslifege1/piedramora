/* ===== Piedra Mora - IDs estables de carta (Fase 0) ===== */
(function (window) {
  'use strict';

  const PM = window.PM = window.PM || {};
  const RE_ID = /^[a-z0-9]+(_[a-z0-9]+)*$/;

  function slugify(texto) {
    return String(texto == null ? '' : texto)
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '_')
      .replace(/_+/g, '_')
      .replace(/^_+|_+$/g, '');
  }

  function existeEn(id, vistos) {
    if (vistos instanceof Set) return vistos.has(id);
    if (Array.isArray(vistos)) return vistos.includes(id);
    return false;
  }

  function idUnico(base, vistos) {
    let id = base;
    let i = 2;
    while (existeEn(id, vistos)) {
      id = `${base}_${i}`;
      i += 1;
    }
    if (vistos instanceof Set) vistos.add(id);
    return id;
  }

  function generarIdProducto(categoriaId, nombre, vistos) {
    const categoria = slugify(categoriaId) || 'sin_categoria';
    const base = `${categoria}_${slugify(nombre) || 'producto'}`;
    return idUnico(base, vistos);
  }

  function generarIdOpcion(productoId, nombre, vistos) {
    const producto = slugify(productoId) || 'producto';
    const base = `${producto}_${slugify(nombre) || 'opcion'}`;
    return idUnico(base, vistos);
  }

  function validarId(id) {
    return RE_ID.test(String(id == null ? '' : id));
  }

  PM.slugify = PM.slugify || slugify;
  PM.generarIdProducto = generarIdProducto;
  PM.generarIdOpcion = generarIdOpcion;
  PM.generarIdAdicional = generarIdOpcion;
  PM.validarId = validarId;
  PM.idUnico = idUnico;
})(window);
