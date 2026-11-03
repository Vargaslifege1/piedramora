(() => {
  'use strict';

  const RUTA_CONFIG = 'data/nube.json';
  const RUTA_CARTA_LOCAL = 'data/cartas.json';
  const BUCKET_IMAGENES = 'carta-imagenes';
  const TAMANO_MAXIMO_IMAGEN = 5 * 1024 * 1024;
  const TIPOS_IMAGEN = ['image/jpeg', 'image/png', 'image/webp', 'image/avif', 'image/gif'];
  let SUCURSALES_POR_DEFECTO = ['maestro-quiroga', 'intendente-lascano'];

  const el = {
    login: document.getElementById('admin-login'),
    panel: document.getElementById('admin-panel'),
    sesion: document.getElementById('admin-sesion'),
    sesionEmail: document.getElementById('admin-sesion-email'),
    formLogin: document.getElementById('form-login'),
    emailWrap: document.getElementById('admin-email-wrap'),
    emailInput: document.getElementById('admin-email'),
    passwordInput: document.getElementById('admin-password'),
    btnLogin: document.getElementById('btn-login'),
    loginEstado: document.getElementById('login-estado'),
    btnLogout: document.getElementById('btn-logout'),
    configPendiente: document.getElementById('admin-config-pendiente'),
    btnGuardar: document.getElementById('btn-guardar'),
    btnRecargar: document.getElementById('btn-recargar'),
    btnExportar: document.getElementById('btn-exportar'),
    estado: document.getElementById('admin-estado'),
    aviso: document.getElementById('admin-aviso'),
    btnNuevaCategoria: document.getElementById('btn-nueva-categoria'),
    listaCategorias: document.getElementById('lista-categorias'),
    sinCategoria: document.getElementById('admin-sin-categoria'),
    detalle: document.getElementById('admin-categoria-detalle'),
    detalleFoto: document.getElementById('detalle-categoria-foto'),
    detalleNombre: document.getElementById('detalle-categoria-nombre'),
    detalleMeta: document.getElementById('detalle-categoria-meta'),
    btnEditarCategoria: document.getElementById('btn-editar-categoria'),
    btnNuevoProducto: document.getElementById('btn-nuevo-producto'),
    categoriaVacia: document.getElementById('admin-categoria-vacia'),
    btnVacioNuevoProducto: document.getElementById('btn-vacio-nuevo-producto'),
    listaProductos: document.getElementById('lista-productos'),
    panelNuevoProducto: document.getElementById('panel-nuevo-producto'),
    productoCategoriaChip: document.getElementById('producto-categoria-chip'),
    btnCerrarFormProducto: document.getElementById('btn-cerrar-form-producto'),
    formProducto: document.getElementById('form-producto'),
    productoNombre: document.getElementById('producto-nombre'),
    productoDescripcion: document.getElementById('producto-descripcion'),
    productoFotoPreview: document.getElementById('producto-foto-preview'),
    productoFotoZona: document.getElementById('producto-foto-zona'),
    btnSubirProducto: document.getElementById('btn-subir-producto'),
    productoFotoFile: document.getElementById('producto-foto-file'),
    productoFotoEstado: document.getElementById('producto-foto-estado'),
    productoDelivery: document.getElementById('producto-delivery'),
    productoMesa: document.getElementById('producto-mesa'),
    productoDeliveryOferta: document.getElementById('producto-delivery-oferta'),
    productoMesaOferta: document.getElementById('producto-mesa-oferta'),
    productoTipoOferta: document.getElementById('producto-tipo-oferta'),
    productoAgotado: document.getElementById('producto-agotado'),
    productoAgotadoPermanente: document.getElementById('producto-agotado-permanente'),
    btnAgregarProducto: document.getElementById('btn-agregar-producto'),
    btnCancelarProducto: document.getElementById('btn-cancelar-producto'),
    productoEstado: document.getElementById('producto-estado'),
    modalCategoria: document.getElementById('modal-categoria'),
    modalCategoriaTitulo: document.getElementById('modal-categoria-titulo'),
    btnCerrarModalCategoria: document.getElementById('btn-cerrar-modal-categoria'),
    formCategoria: document.getElementById('form-categoria'),
    categoriaNombre: document.getElementById('categoria-nombre'),
    categoriaFotoPreview: document.getElementById('categoria-foto-preview'),
    categoriaFotoZona: document.getElementById('categoria-foto-zona'),
    btnSubirCategoria: document.getElementById('btn-subir-categoria'),
    categoriaFotoFile: document.getElementById('categoria-foto-file'),
    categoriaFotoEstado: document.getElementById('categoria-foto-estado'),
    categoriaEstado: document.getElementById('categoria-estado'),
    btnGuardarCategoria: document.getElementById('btn-guardar-categoria'),
    btnCancelarCategoria: document.getElementById('btn-cancelar-categoria')
  };

  let config = null;
  let cliente = null;
  let carta = null;
  let categoriaActivaId = null;
  let cambiosPendientes = false;
  let publicacionLocalRiesgosa = false;
  let guardando = false;
  let subidasPendientes = 0;
  let productosExpandidos = new Set();
  const previewsTemporales = new Set();
  const tokensUploadProducto = new Map();

  let modalCategoriaModo = 'crear';
  let categoriaEditandoId = null;
  let fotoCategoriaSeleccionada = '';
  let subiendoCategoria = false;
  let tokenUploadCategoria = 0;

  let fotoNuevaProductoUrl = '';
  let subiendoFotoNueva = false;
  let tokenUploadNuevo = 0;

  function escaparHtml(valor) {
    return String(valor === undefined || valor === null ? '' : valor)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function formatearPrecio(valor) {
    const numero = Number(valor);
    if (!Number.isFinite(numero)) return '$0';
    try {
      return new Intl.NumberFormat('es-AR', { style: 'currency', currency: 'ARS', maximumFractionDigits: 0 }).format(numero);
    } catch (error) {
      return `$${numero}`;
    }
  }

  const MAPA_CATEGORIAS_LEGACY = {
    promos: 'promo',
    hamburguesas: 'burger',
    pizzas: 'pizza',
    lomitos: 'lomo',
    milanesas: 'milanesa',
    barrolucos: 'barroluco',
    bebidas: 'bebida'
  };

  function normalizarCarta(contenido) {
    const categoriasFuente = Array.isArray(contenido && contenido.categorias) ? contenido.categorias : [];
    const productos = Array.isArray(contenido && contenido.productos) ? contenido.productos : [];
    const mapa = new Map();
    const usados = new Set();
    const categorias = [];

    categoriasFuente.forEach(cat => {
      if (!cat) return;
      const idAnterior = String(cat.id || '').trim();
      if (!idAnterior) return;
      const idNuevo = MAPA_CATEGORIAS_LEGACY[idAnterior] || idAnterior;
      mapa.set(idAnterior, idNuevo);
      if (usados.has(idNuevo)) return;
      usados.add(idNuevo);
      cat.id = idNuevo;
      categorias.push(cat);
    });

    productos.forEach(producto => {
      if (!producto) return;
      const categoriaAnterior = String(producto.categoria || '').trim();
      producto.categoria = mapa.get(categoriaAnterior)
        || MAPA_CATEGORIAS_LEGACY[categoriaAnterior]
        || categoriaAnterior;
    });

    return { categorias, productos };
  }

  function asegurarCategoriaPromos() {
    if (!carta) return;
    if (!Array.isArray(carta.categorias)) carta.categorias = [];
    const existe = carta.categorias.some(cat => cat && cat.id === 'promo');
    if (!existe) {
      carta.categorias.unshift({
        id: 'promo',
        nombre: 'PROMOS',
        foto: 'assets/categoria-delivery.webp'
      });
    }
  }

  function categoriaPorId(id) {
    if (!carta) return null;
    return carta.categorias.find(cat => cat && cat.id === id) || null;
  }

  function categoriaValida(id) {
    return !!categoriaPorId(id);
  }

  function nombreCategoria(id) {
    const cat = categoriaPorId(id);
    return cat ? cat.nombre : (id || 'Sin categoría');
  }

  function esRutaImagenSegura(valor) {
    return PM.esRutaImagenSegura(valor);
  }

  function rutaImagenCategoria(cat) {
    const foto = cat && typeof cat.foto === 'string' ? cat.foto.trim() : '';
    return esRutaImagenSegura(foto) ? foto : 'assets/logo.webp';
  }

  function rutaImagenProducto(producto) {
    const foto = producto && typeof producto.foto === 'string' ? producto.foto.trim() : '';
    if (esRutaImagenSegura(foto)) return foto;
    const cat = categoriaPorId(producto && producto.categoria);
    return cat ? rutaImagenCategoria(cat) : 'assets/logo.webp';
  }

  function tipoOfertaProducto(producto) {
    return producto && (producto.tipoOferta === 'dia' || producto.tipoOferta === 'semana')
      ? producto.tipoOferta
      : '';
  }

  function etiquetaTipoOferta(tipo) {
    if (tipo === 'dia') return 'Oferta del día';
    if (tipo === 'semana') return 'Oferta de la semana';
    return 'Sin oferta';
  }

  function productosDeCategoria(id) {
    if (!carta || !Array.isArray(carta.productos)) return [];
    return carta.productos.filter(prod => prod && prod.categoria === id);
  }

  function contarOfertas(productos) {
    return productos.filter(prod => tipoOfertaProducto(prod)).length;
  }

  function opcionesCategorias(seleccionada) {
    if (!carta) return '';
    return carta.categorias
      .filter(cat => cat && cat.id)
      .map(cat => `<option value="${escaparHtml(cat.id)}"${cat.id === seleccionada ? ' selected' : ''}>${escaparHtml(cat.nombre || cat.id)}</option>`)
      .join('');
  }

  function mostrarEstado(elemento, texto, tipo = '') {
    if (!elemento) return;
    elemento.textContent = texto || '';
    if (tipo) elemento.dataset.tipo = tipo;
    else elemento.removeAttribute('data-tipo');
  }

  function mostrarAviso(texto, tipo = 'info') {
    if (!el.aviso) return;
    if (!texto) {
      el.aviso.hidden = true;
      el.aviso.textContent = '';
      return;
    }
    el.aviso.hidden = false;
    el.aviso.dataset.tipo = tipo;
    el.aviso.textContent = texto;
  }

  function crearPreviewTemporal(archivo) {
    if (!archivo || typeof URL === 'undefined' || typeof URL.createObjectURL !== 'function') return '';
    try {
      const url = URL.createObjectURL(archivo);
      previewsTemporales.add(url);
      return url;
    } catch (error) {
      return '';
    }
  }

  function revocarPreviewTemporal(url) {
    if (!url || !previewsTemporales.has(url)) return;
    previewsTemporales.delete(url);
    try { URL.revokeObjectURL(url); } catch (error) {}
  }

  function aplicarPreviewImagen(imagen, url) {
    if (!imagen || !url) return;
    imagen.dataset.fallback = '';
    imagen.src = url;
  }

  function marcarCambios() {
    cambiosPendientes = true;
    mostrarEstado(el.estado, 'Cambios sin guardar', 'pendiente');
  }

  function actualizarBotonGuardar() {
    if (!el.btnGuardar) return;
    const bloqueado = guardando || subidasPendientes > 0;
    el.btnGuardar.disabled = bloqueado;
    if (guardando) el.btnGuardar.textContent = 'Guardando...';
    else if (subidasPendientes > 0) el.btnGuardar.textContent = 'Subiendo imágenes...';
    else el.btnGuardar.textContent = 'Guardar y publicar';
  }

  function actualizarBotonAgregar() {
    if (!el.btnAgregarProducto) return;
    el.btnAgregarProducto.disabled = subiendoFotoNueva;
    el.btnAgregarProducto.textContent = subiendoFotoNueva ? 'Subiendo imagen...' : 'Agregar producto';
  }

  function actualizarBotonGuardarCategoria() {
    if (!el.btnGuardarCategoria) return;
    el.btnGuardarCategoria.disabled = subiendoCategoria;
    el.btnGuardarCategoria.textContent = subiendoCategoria ? 'Subiendo imagen...' : 'Guardar categoría';
  }

  function configValida() {
    return !!(config && config.supabaseUrl && config.supabaseAnonKey);
  }

  function tablaCarta() {
    return (config && config.tabla) || 'carta';
  }

  function filaCarta() {
    return config && config.filaId !== undefined ? config.filaId : 1;
  }

  async function cargarConfig() {
    try {
      const resp = await fetch(RUTA_CONFIG, { cache: 'no-store' });
      if (!resp.ok) throw new Error('No se pudo leer data/nube.json');
      config = await resp.json();
    } catch (error) {
      config = null;
      console.warn(error.message);
    }
  }

  async function cargarSucursalesConfig() {
    try {
      const resp = await fetch('data/sucursales.json', { cache: 'no-store' });
      if (!resp.ok) throw new Error('No se pudo leer data/sucursales.json');
      const datos = await resp.json();
      const ids = Array.isArray(datos.sucursales)
        ? datos.sucursales.map(sucursal => String(sucursal.id || '').trim()).filter(Boolean)
        : [];
      if (ids.length > 0) SUCURSALES_POR_DEFECTO = ids;
    } catch (error) {
      console.warn(error.message);
    }
  }

  function inicializarCliente() {
    if (!configValida()) return null;
    if (!window.supabase || typeof window.supabase.createClient !== 'function') return null;

    cliente = window.supabase.createClient(config.supabaseUrl, config.supabaseAnonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: false
      }
    });

    return cliente;
  }

  function mostrarLogin() {
    if (el.login) el.login.hidden = false;
    if (el.panel) el.panel.hidden = true;
    if (el.sesion) el.sesion.hidden = true;
    if (el.passwordInput) el.passwordInput.value = '';
    cerrarModalCategoria();
    actualizarBotonGuardar();
  }

  async function mostrarPanel(usuario) {
    if (!usuario) return;

    try {
      const { data: esAdmin, error } = await cliente.rpc('es_admin');
      if (error) throw error;
      if (esAdmin !== true) {
        mostrarEstado(el.loginEstado, 'Este usuario no tiene permisos de administrador.', 'error');
        mostrarLogin();
        if (cliente) await cliente.auth.signOut();
        return;
      }
    } catch (error) {
      const detalle = error && error.message ? error.message : 'No se pudo verificar el permiso.';
      mostrarEstado(el.loginEstado, `No se pudo verificar el permiso de administrador: ${detalle}`, 'error');
      mostrarLogin();
      if (cliente) await cliente.auth.signOut();
      return;
    }

    const yaVisible = el.panel && !el.panel.hidden;

    if (el.login) el.login.hidden = true;
    if (el.panel) el.panel.hidden = false;
    if (el.sesion) el.sesion.hidden = false;
    if (el.sesionEmail) el.sesionEmail.textContent = usuario.email || 'Administrador';

    if (!yaVisible) await cargarCarta();
  }

  async function cargarCarta() {
    if (!cliente) return;
    mostrarAviso('');
    mostrarEstado(el.estado, 'Cargando carta...');

    let contenido = null;
    let desdeNube = false;
    let errorNube = null;

    try {
      const { data, error } = await cliente
        .from(tablaCarta())
        .select('contenido')
        .eq('id', filaCarta())
        .maybeSingle();

      if (error) throw error;
      if (data && data.contenido) {
        contenido = data.contenido;
        desdeNube = true;
      }
    } catch (error) {
      errorNube = error;
      console.warn('No se pudo leer la carta desde Supabase:', error.message || error);
    }

    if (!contenido) {
      try {
        const resp = await fetch(RUTA_CARTA_LOCAL, { cache: 'no-store' });
        if (!resp.ok) throw new Error('No se pudo leer data/cartas.json');
        contenido = await resp.json();
      } catch (error) {
        mostrarEstado(el.estado, 'No se pudo cargar la carta local', 'error');
        mostrarAviso('Revisá data/cartas.json y la configuración de Supabase.', 'error');
        return;
      }
    }

    const activaAnterior = categoriaActivaId;
    carta = normalizarCarta(contenido);
    asegurarCategoriaPromos();
    categoriaActivaId = categoriaValida(activaAnterior)
      ? activaAnterior
      : (categoriaValida('promo') ? 'promo' : (carta.categorias[0] ? carta.categorias[0].id : null));
    publicacionLocalRiesgosa = !!errorNube;
    productosExpandidos.clear();
    cambiosPendientes = false;
    cerrarFormularioProducto();
    cerrarModalCategoria();
    renderizarTodo();

    if (desdeNube) {
      mostrarEstado(el.estado, 'Carta sincronizada con la nube', 'ok');
      mostrarAviso('');
    } else {
      mostrarEstado(el.estado, 'Carta local cargada', 'pendiente');
      const detalle = errorNube
        ? `No se pudo leer Supabase (${errorNube.message || 'error de conexión'}). Se cargó la copia local.`
        : 'La nube todavía no tiene contenido. Se cargó la copia local.';
      mostrarAviso(`${detalle} Guardá para publicar esta carta en la nube.`, 'info');
    }
  }

  function renderizarTodo() {
    renderizarCategorias();
    renderizarDetalleCategoria();
    actualizarBotonGuardar();
    actualizarBotonAgregar();
    actualizarBotonGuardarCategoria();
  }

  function renderizarCategorias() {
    if (!el.listaCategorias || !carta) return;

    if (!carta.categorias.length) {
      el.listaCategorias.innerHTML = '<p class="admin-vacio">Todavía no hay categorías. Creá la primera para empezar.</p>';
      return;
    }

    el.listaCategorias.innerHTML = carta.categorias.map(cat => {
      if (!cat || !cat.id) return '';
      const productos = productosDeCategoria(cat.id);
      const ofertas = contarOfertas(productos);
      const activa = cat.id === categoriaActivaId;

      return `
        <article class="admin-cat-card${activa ? ' activa' : ''}" data-id="${escaparHtml(cat.id)}">
          <button type="button" class="admin-cat-open" data-accion="seleccionar-categoria" data-id="${escaparHtml(cat.id)}" aria-pressed="${activa ? 'true' : 'false'}">
            <img class="admin-cat-foto" src="${escaparHtml(rutaImagenCategoria(cat))}" alt="" loading="lazy" decoding="async">
            <span class="admin-cat-sombra"></span>
            <span class="admin-cat-contenido">
              <span class="admin-cat-nombre">${escaparHtml(cat.nombre || cat.id)}</span>
              <span class="admin-cat-meta">${productos.length} producto${productos.length === 1 ? '' : 's'}</span>
            </span>
            ${ofertas > 0 ? `<span class="admin-cat-ofertas">${ofertas} en oferta</span>` : ''}
          </button>
          <button type="button" class="admin-cat-editar" data-accion="editar-categoria" data-id="${escaparHtml(cat.id)}">Editar</button>
        </article>
      `;
    }).join('');
  }

  function seleccionarCategoria(id, hacerScroll = false) {
    if (!categoriaValida(id)) return;
    if (categoriaActivaId !== id) {
      categoriaActivaId = id;
      productosExpandidos.clear();
      cerrarFormularioProducto();
    }
    renderizarTodo();
    if (hacerScroll && el.detalle && typeof el.detalle.scrollIntoView === 'function') {
      requestAnimationFrame(() => {
        el.detalle.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
    }
  }

  function renderizarDetalleCategoria() {
    if (!el.detalle) return;
    const cat = categoriaPorId(categoriaActivaId);

    if (!cat) {
      el.detalle.hidden = true;
      if (el.sinCategoria) el.sinCategoria.hidden = false;
      if (el.listaProductos) el.listaProductos.innerHTML = '';
      return;
    }

    if (el.sinCategoria) el.sinCategoria.hidden = true;
    el.detalle.hidden = false;

    const productos = productosDeCategoria(cat.id);
    const ofertas = contarOfertas(productos);

    if (el.detalleFoto) {
      el.detalleFoto.dataset.fallback = '';
      el.detalleFoto.src = rutaImagenCategoria(cat);
    }
    if (el.detalleNombre) el.detalleNombre.textContent = cat.nombre || cat.id;
    if (el.detalleMeta) {
      el.detalleMeta.textContent = `${productos.length} producto${productos.length === 1 ? '' : 's'}${ofertas > 0 ? ` · ${ofertas} en oferta` : ''}`;
    }

    renderizarProductos(productos);
  }

  function renderizarProductos(productos) {
    if (!el.listaProductos) return;

    if (!productos.length) {
      el.listaProductos.innerHTML = '';
      if (el.categoriaVacia) el.categoriaVacia.hidden = false;
      return;
    }

    if (el.categoriaVacia) el.categoriaVacia.hidden = true;

    el.listaProductos.innerHTML = productos.map(producto => {
      const id = producto.id;
      const abierto = productosExpandidos.has(id);
      const tipo = tipoOfertaProducto(producto);
      const precios = producto.precios || {};
      const agotado = PM.productoEstaAgotado(producto);
      const agotadoPermanente = producto.agotado_hasta_nuevo_aviso === true;
      const ofertaBadge = tipo
        ? `<span class="admin-badge admin-badge-${tipo}">${etiquetaTipoOferta(tipo)}</span>`
        : '';
      const agotadoBadge = agotado
        ? `<span class="admin-badge admin-badge-agotado">${agotadoPermanente ? 'AGOTADO PERMANENTE' : 'AGOTADO HOY'}</span>`
        : '';

      return `
        <article class="admin-producto${abierto ? ' abierto' : ''}" data-id="${escaparHtml(id)}" data-oferta="${tipo || 'ninguna'}">
          <div class="admin-prod-resumen">
            <img class="admin-prod-thumb" src="${escaparHtml(rutaImagenProducto(producto))}" alt="" loading="lazy" decoding="async">
            <div class="admin-prod-info">
              <div class="admin-prod-titulo-fila">
                <h3 class="admin-prod-nombre">${escaparHtml(producto.nombre || id)}</h3>
                ${ofertaBadge}
                ${agotadoBadge}
              </div>
              <p class="admin-prod-desc">${escaparHtml(producto.descripcion || 'Sin descripción')}</p>
              <p class="admin-prod-precios">Delivery ${formatearPrecio(precios.delivery)} · Mesa ${formatearPrecio(precios.mesa)}</p>
            </div>
            <div class="admin-prod-acciones">
              <button type="button" class="btn-secundario" data-accion="toggle-producto" data-id="${escaparHtml(id)}" aria-expanded="${abierto ? 'true' : 'false'}">${abierto ? 'Cerrar' : 'Editar'}</button>
              <button type="button" class="btn-peligro" data-accion="eliminar-producto" data-id="${escaparHtml(id)}">Eliminar</button>
            </div>
          </div>

          <div class="admin-prod-editor" ${abierto ? '' : 'hidden'}>
            <div class="admin-grid-campos">
              <label class="admin-campo admin-campo-nombre">
                <span>Nombre</span>
                <input type="text" data-campo-producto="nombre" value="${escaparHtml(producto.nombre || '')}">
              </label>

              <label class="admin-campo admin-campo-categoria">
                <span>Categoría</span>
                <select data-campo-producto="categoria">
                  ${opcionesCategorias(producto.categoria)}
                </select>
              </label>

              <label class="admin-campo admin-campo-descripcion">
                <span>Descripción</span>
                <textarea rows="2" data-campo-producto="descripcion">${escaparHtml(producto.descripcion || '')}</textarea>
              </label>

              <div class="admin-campo admin-campo-ancho">
                <span>Imagen del producto</span>
                <div class="admin-upload admin-upload-compacta" data-upload-zona title="Hacé clic para cambiar la imagen">
                  <img class="admin-upload-preview" data-preview-producto="${escaparHtml(id)}" src="${escaparHtml(rutaImagenProducto(producto))}" alt="Vista previa">
                  <div class="admin-upload-info">
                    <button type="button" class="btn-secundario" data-accion="subir-imagen-producto" data-id="${escaparHtml(id)}">Cambiar imagen</button>
                    <input type="file" class="admin-file-input" accept="image/*" data-file-producto aria-label="Cambiar imagen del producto">
                    <p class="admin-upload-ayuda">JPG, PNG, WEBP, AVIF o GIF · máximo 5 MB</p>
                    <p class="admin-estado" data-upload-producto="${escaparHtml(id)}" aria-live="polite"></p>
                  </div>
                </div>
              </div>

              <label class="admin-campo">
                <span>Precio delivery</span>
                <input type="number" min="0" step="100" data-campo-producto="delivery" value="${escaparHtml(precios.delivery === undefined ? '' : precios.delivery)}">
              </label>

              <label class="admin-campo">
                <span>Precio mesa</span>
                <input type="number" min="0" step="100" data-campo-producto="mesa" value="${escaparHtml(precios.mesa === undefined ? '' : precios.mesa)}">
              </label>

              <label class="admin-campo">
                <span>Tipo de oferta</span>
                <select data-campo-producto="tipoOferta">
                  <option value=""${tipo === '' ? ' selected' : ''}>Sin oferta</option>
                  <option value="dia"${tipo === 'dia' ? ' selected' : ''}>Oferta del día</option>
                  <option value="semana"${tipo === 'semana' ? ' selected' : ''}>Oferta de la semana</option>
                </select>
              </label>

              <label class="admin-campo">
                <span>Delivery oferta</span>
                <input type="number" min="0" step="100" data-campo-producto="delivery_oferta" value="${escaparHtml(producto.delivery_oferta === undefined ? '' : producto.delivery_oferta)}">
              </label>

              <label class="admin-campo">
                <span>Mesa oferta</span>
                <input type="number" min="0" step="100" data-campo-producto="mesa_oferta" value="${escaparHtml(producto.mesa_oferta === undefined ? '' : producto.mesa_oferta)}">
              </label>

              <label class="admin-campo admin-campo-check">
                <span>Agotado hoy</span>
                <input type="checkbox" data-campo-producto="agotado" ${agotado ? 'checked' : ''}>
              </label>

              <label class="admin-campo admin-campo-check">
                <span>Hasta nuevo aviso</span>
                <input type="checkbox" data-campo-producto="agotado_hasta_nuevo_aviso" ${agotadoPermanente ? 'checked' : ''}>
              </label>
            </div>
          </div>
        </article>
      `;
    }).join('');
  }

  function buscarProducto(id) {
    if (!carta) return null;
    return carta.productos.find(prod => prod && prod.id === id) || null;
  }

  function buscarTarjetaProducto(id) {
    if (!el.listaProductos) return null;
    return Array.from(el.listaProductos.querySelectorAll('.admin-producto'))
      .find(card => card.dataset.id === id) || null;
  }

  function actualizarResumenPrecios(card, producto) {
    const precios = card && card.querySelector('.admin-prod-precios');
    if (!precios || !producto) return;
    const valores = producto.precios || {};
    precios.textContent = `Delivery ${formatearPrecio(valores.delivery)} · Mesa ${formatearPrecio(valores.mesa)}`;
  }

  function actualizarCampoProducto(control) {
    if (!control || !carta) return;
    const contenedor = control.closest('[data-id]');
    if (!contenedor) return;

    const producto = buscarProducto(contenedor.dataset.id);
    if (!producto) return;

    const campo = control.dataset.campoProducto;
    if (!campo) return;

    if (campo === 'nombre') {
      producto.nombre = control.value;
      const titulo = contenedor.querySelector('.admin-prod-nombre');
      if (titulo) titulo.textContent = control.value.trim() || producto.id;
    } else if (campo === 'descripcion') {
      producto.descripcion = control.value;
      const desc = contenedor.querySelector('.admin-prod-desc');
      if (desc) desc.textContent = control.value.trim() || 'Sin descripción';
    } else if (campo === 'categoria') {
      if (!categoriaValida(control.value)) return;

      const categoriaAnterior = producto.categoria;
      const idAnterior = producto.id;
      const sufijo = idAnterior.startsWith(`${categoriaAnterior}_`)
        ? idAnterior.slice(categoriaAnterior.length + 1)
        : idAnterior;
      const idsOcupados = new Set(
        carta.productos
          .filter(otro => otro && otro !== producto)
          .map(otro => otro.id)
      );
      const idNuevo = PM.idUnico(`${control.value}_${sufijo}`, idsOcupados);

      producto.id = idNuevo;
      producto.categoria = control.value;

      if (producto.variaciones && Array.isArray(producto.variaciones.opciones)) {
        producto.variaciones.opciones.forEach(opcion => {
          if (opcion && typeof opcion.id === 'string' && opcion.id.startsWith(idAnterior)) {
            opcion.id = idNuevo + opcion.id.slice(idAnterior.length);
          }
        });
      }

      if (Array.isArray(producto.adicionales)) {
        producto.adicionales.forEach(adicional => {
          if (adicional && typeof adicional.id === 'string' && adicional.id.startsWith(idAnterior)) {
            adicional.id = idNuevo + adicional.id.slice(idAnterior.length);
          }
        });
      }

      productosExpandidos.delete(idAnterior);
      productosExpandidos.add(idNuevo);
      tokensUploadProducto.delete(idAnterior);
      marcarCambios();
      renderizarCategorias();
      renderizarDetalleCategoria();
      return;
    } else if (campo === 'delivery' || campo === 'mesa') {
      if (!producto.precios || typeof producto.precios !== 'object') producto.precios = {};
      const valor = Number(control.value);
      if (control.value === '' || !Number.isFinite(valor) || valor < 0) delete producto.precios[campo];
      else producto.precios[campo] = valor;
      actualizarResumenPrecios(contenedor, producto);
    } else if (campo === 'tipoOferta') {
      if (control.value === 'dia' || control.value === 'semana') producto.tipoOferta = control.value;
      else delete producto.tipoOferta;
      productosExpandidos.add(producto.id);
      marcarCambios();
      renderizarCategorias();
      renderizarDetalleCategoria();
      return;
    } else if (campo === 'delivery_oferta' || campo === 'mesa_oferta') {
      const valor = Number(control.value);
      if (control.value === '' || !Number.isFinite(valor) || valor <= 0) delete producto[campo];
      else producto[campo] = valor;
    } else if (campo === 'agotado') {
      const activo = !!control.checked;
      producto.agotado = activo;

      if (activo) {
        producto.agotado_fecha = PM.hoyArgentina();
      } else {
        producto.agotado_fecha = null;
        producto.agotado_hasta_nuevo_aviso = false;
      }

      productosExpandidos.add(producto.id);
      marcarCambios();
      renderizarCategorias();
      renderizarDetalleCategoria();
      return;
    } else if (campo === 'agotado_hasta_nuevo_aviso') {
      const permanente = !!control.checked;
      producto.agotado_hasta_nuevo_aviso = permanente;

      if (permanente) {
        producto.agotado = true;
        producto.agotado_fecha = producto.agotado_fecha || PM.hoyArgentina();
      } else if (producto.agotado === true && producto.agotado_fecha !== PM.hoyArgentina()) {
        producto.agotado = false;
        producto.agotado_fecha = null;
      }

      productosExpandidos.add(producto.id);
      marcarCambios();
      renderizarCategorias();
      renderizarDetalleCategoria();
      return;
    }

    marcarCambios();
  }

  function toggleProducto(id) {
    if (productosExpandidos.has(id)) productosExpandidos.delete(id);
    else productosExpandidos.add(id);

    const card = buscarTarjetaProducto(id);
    if (!card) return;
    const editor = card.querySelector('.admin-prod-editor');
    const boton = card.querySelector('[data-accion="toggle-producto"]');
    const abierto = productosExpandidos.has(id);
    card.classList.toggle('abierto', abierto);
    if (editor) editor.hidden = !abierto;
    if (boton) {
      boton.textContent = abierto ? 'Cerrar' : 'Editar';
      boton.setAttribute('aria-expanded', abierto ? 'true' : 'false');
    }
  }

  function eliminarProducto(id) {
    const producto = buscarProducto(id);
    if (!producto) return;

    const nombre = producto.nombre || producto.id;
    if (!window.confirm(`¿Eliminar "${nombre}" de la carta? El cambio se publica al guardar.`)) return;

    carta.productos = carta.productos.filter(prod => prod && prod.id !== id);
    productosExpandidos.delete(id);
    renderizarCategorias();
    renderizarDetalleCategoria();
    marcarCambios();
  }

  function validarArchivoImagen(archivo) {
    if (!archivo) throw new Error('No se seleccionó ningún archivo.');
    const tipo = String(archivo.type || '').toLowerCase();
    const extensionValida = /\.(jpe?g|png|webp|avif|gif)$/i.test(archivo.name || '');
    if (!TIPOS_IMAGEN.includes(tipo) && !extensionValida) {
      throw new Error('El archivo debe ser una imagen JPG, PNG, WEBP, AVIF o GIF.');
    }
    if (archivo.size > TAMANO_MAXIMO_IMAGEN) {
      throw new Error('La imagen supera el máximo de 5 MB.');
    }
  }

  function extensionImagen(archivo) {
    const tipo = String(archivo.type || '').toLowerCase();
    const mapa = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
      'image/avif': 'avif',
      'image/gif': 'gif'
    };
    if (mapa[tipo]) return mapa[tipo];
    const coincidencia = String(archivo.name || '').toLowerCase().match(/\.(jpe?g|png|webp|avif|gif)$/);
    return coincidencia ? coincidencia[1].replace('jpeg', 'jpg') : 'webp';
  }

  async function subirImagen(archivo, carpeta) {
    if (!cliente) throw new Error('Supabase no está disponible.');
    validarArchivoImagen(archivo);

    const extension = extensionImagen(archivo);
    const nombre = `${Date.now()}-${Math.random().toString(36).slice(2, 9)}.${extension}`;
    const ruta = `${carpeta}/${nombre}`;

    const { error } = await cliente.storage
      .from(BUCKET_IMAGENES)
      .upload(ruta, archivo, {
        cacheControl: '3600',
        upsert: false,
        contentType: archivo.type || undefined
      });

    if (error) throw new Error(error.message || 'No se pudo subir la imagen.');

    const { data } = cliente.storage.from(BUCKET_IMAGENES).getPublicUrl(ruta);
    if (!data || !data.publicUrl) throw new Error('No se pudo obtener la URL pública de la imagen.');
    return data.publicUrl;
  }

  async function subirImagenProducto(id, archivo) {
    const producto = buscarProducto(id);
    if (!producto) return;

    const card = buscarTarjetaProducto(id);
    const estado = card ? card.querySelector(`[data-upload-producto="${id}"]`) : null;

    try {
      validarArchivoImagen(archivo);
    } catch (error) {
      mostrarEstado(estado, error.message, 'error');
      return;
    }

    const token = (tokensUploadProducto.get(id) || 0) + 1;
    tokensUploadProducto.set(id, token);

    const preview = card ? card.querySelector(`[data-preview-producto="${id}"]`) : null;
    const previewAnterior = preview ? preview.src : '';
    const previewTemporal = crearPreviewTemporal(archivo);
    let subidaOk = false;

    if (previewTemporal) aplicarPreviewImagen(preview, previewTemporal);

    subidasPendientes += 1;
    actualizarBotonGuardar();
    mostrarEstado(estado, 'Subiendo imagen...', 'pendiente');

    try {
      const url = await subirImagen(archivo, 'productos');
      if (token !== tokensUploadProducto.get(id)) return;
      const actual = buscarProducto(id);
      if (!actual) return;
      actual.foto = url;
      subidaOk = true;
      marcarCambios();
      actualizarImagenProductoEnDom(id, url);
      mostrarEstado(estado, 'Imagen actualizada', 'ok');
    } catch (error) {
      if (token === tokensUploadProducto.get(id)) {
        if (preview && previewAnterior) aplicarPreviewImagen(preview, previewAnterior);
        mostrarEstado(estado, `Error: ${error.message}`, 'error');
      }
      mostrarAviso('No se pudo subir la imagen. Verificá que el bucket carta-imagenes y sus permisos existan.', 'error');
    } finally {
      if (previewTemporal) {
        if (token === tokensUploadProducto.get(id) && subidaOk && preview && preview.src === previewTemporal) {
          aplicarPreviewImagen(preview, producto.foto || previewAnterior);
        }
        revocarPreviewTemporal(previewTemporal);
      }
      subidasPendientes = Math.max(0, subidasPendientes - 1);
      actualizarBotonGuardar();
    }
  }

  function actualizarImagenProductoEnDom(id, url) {
    const card = buscarTarjetaProducto(id);
    if (!card) return;
    const imagenes = card.querySelectorAll('.admin-prod-thumb, [data-preview-producto]');
    imagenes.forEach(imagen => {
      imagen.dataset.fallback = '';
      imagen.src = url;
    });
  }

  function abrirFormularioProducto() {
    const cat = categoriaPorId(categoriaActivaId);
    if (!cat) return;

    tokenUploadNuevo += 1;
    fotoNuevaProductoUrl = '';
    subiendoFotoNueva = false;
    el.formProducto.reset();
    if (el.productoCategoriaChip) el.productoCategoriaChip.textContent = cat.nombre || cat.id;
    if (el.productoFotoFile) el.productoFotoFile.value = '';
    if (el.productoFotoPreview) {
      el.productoFotoPreview.dataset.fallback = '';
      el.productoFotoPreview.src = rutaImagenCategoria(cat);
    }
    mostrarEstado(el.productoFotoEstado, '');
    mostrarEstado(el.productoEstado, '');
    actualizarBotonAgregar();
    el.panelNuevoProducto.hidden = false;

    requestAnimationFrame(() => {
      if (typeof el.panelNuevoProducto.scrollIntoView === 'function') {
        el.panelNuevoProducto.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
      if (el.productoNombre) el.productoNombre.focus({ preventScroll: true });
    });
  }

  function cerrarFormularioProducto() {
    tokenUploadNuevo += 1;
    fotoNuevaProductoUrl = '';
    subiendoFotoNueva = false;
    if (el.panelNuevoProducto) el.panelNuevoProducto.hidden = true;
    if (el.formProducto) el.formProducto.reset();
    if (el.productoFotoFile) el.productoFotoFile.value = '';
    if (el.productoFotoPreview) {
      el.productoFotoPreview.dataset.fallback = '';
      el.productoFotoPreview.src = 'assets/logo.webp';
    }
    mostrarEstado(el.productoFotoEstado, '');
    mostrarEstado(el.productoEstado, '');
    actualizarBotonAgregar();
  }

  async function subirImagenNueva(archivo) {
    try {
      validarArchivoImagen(archivo);
    } catch (error) {
      mostrarEstado(el.productoFotoEstado, error.message, 'error');
      return;
    }

    const token = ++tokenUploadNuevo;
    const previewAnterior = el.productoFotoPreview ? el.productoFotoPreview.src : '';
    const previewTemporal = crearPreviewTemporal(archivo);
    let subidaOk = false;

    if (previewTemporal) aplicarPreviewImagen(el.productoFotoPreview, previewTemporal);

    subiendoFotoNueva = true;
    subidasPendientes += 1;
    actualizarBotonAgregar();
    actualizarBotonGuardar();
    mostrarEstado(el.productoFotoEstado, 'Subiendo imagen...', 'pendiente');

    try {
      const url = await subirImagen(archivo, 'productos');
      if (token !== tokenUploadNuevo) return;
      fotoNuevaProductoUrl = url;
      subidaOk = true;
      aplicarPreviewImagen(el.productoFotoPreview, url);
      mostrarEstado(el.productoFotoEstado, 'Imagen lista', 'ok');
    } catch (error) {
      if (token === tokenUploadNuevo) {
        if (previewAnterior) aplicarPreviewImagen(el.productoFotoPreview, previewAnterior);
        mostrarEstado(el.productoFotoEstado, `Error: ${error.message}`, 'error');
      }
      mostrarAviso('No se pudo subir la imagen. Verificá que el bucket carta-imagenes y sus permisos existan.', 'error');
    } finally {
      if (previewTemporal) {
        if (token === tokenUploadNuevo && !subidaOk && previewAnterior) {
          aplicarPreviewImagen(el.productoFotoPreview, previewAnterior);
        }
        revocarPreviewTemporal(previewTemporal);
      }
      subidasPendientes = Math.max(0, subidasPendientes - 1);
      if (token === tokenUploadNuevo) {
        subiendoFotoNueva = false;
        actualizarBotonAgregar();
      }
      actualizarBotonGuardar();
    }
  }

  function agregarProducto(evento) {
    evento.preventDefault();
    const cat = categoriaPorId(categoriaActivaId);
    if (!cat) {
      mostrarEstado(el.productoEstado, 'Seleccioná una categoría antes de agregar un producto.', 'error');
      return;
    }

    if (subiendoFotoNueva) {
      mostrarEstado(el.productoEstado, 'Esperá a que termine de subir la imagen.', 'pendiente');
      return;
    }

    const nombre = el.productoNombre.value.trim();
    const descripcion = el.productoDescripcion.value.trim();
    const delivery = Number(el.productoDelivery.value);
    const mesa = Number(el.productoMesa.value);
    const tipo = el.productoTipoOferta.value === 'dia' || el.productoTipoOferta.value === 'semana'
      ? el.productoTipoOferta.value
      : '';

    if (!nombre) {
      mostrarEstado(el.productoEstado, 'Escribí un nombre para el producto.', 'error');
      return;
    }

    if (!Number.isFinite(delivery) || delivery <= 0 || !Number.isFinite(mesa) || mesa <= 0) {
      mostrarEstado(el.productoEstado, 'Los precios de delivery y mesa deben ser mayores a cero.', 'error');
      return;
    }

    const idsExistentes = new Set(
      carta.productos
        .map(producto => producto && producto.id)
        .filter(Boolean)
    );
    const idProducto = PM.generarIdProducto(cat.id, nombre, idsExistentes);
    const agotado = !!(
      (el.productoAgotado && el.productoAgotado.checked)
      || (el.productoAgotadoPermanente && el.productoAgotadoPermanente.checked)
    );
    const permanente = !!(el.productoAgotadoPermanente && el.productoAgotadoPermanente.checked);

    const producto = {
      id: idProducto,
      categoria: cat.id,
      nombre: nombre,
      foto: fotoNuevaProductoUrl || rutaImagenCategoria(cat),
      sucursales: SUCURSALES_POR_DEFECTO.slice(),
      precios: {
        delivery: delivery,
        mesa: mesa
      },
      agotado: agotado,
      agotado_fecha: agotado ? PM.hoyArgentina() : null,
      agotado_hasta_nuevo_aviso: agotado ? permanente : false
    };

    if (descripcion) producto.descripcion = descripcion;

    if (tipo) {
      const deliveryOferta = Number(el.productoDeliveryOferta.value);
      const mesaOferta = Number(el.productoMesaOferta.value);

      if (!Number.isFinite(deliveryOferta) || deliveryOferta <= 0 || !Number.isFinite(mesaOferta) || mesaOferta <= 0) {
        mostrarEstado(el.productoEstado, 'Completá ambos precios de oferta o elegí "Sin oferta".', 'error');
        return;
      }

      if (deliveryOferta >= delivery || mesaOferta >= mesa) {
        mostrarEstado(el.productoEstado, 'Los precios de oferta deben ser menores a los originales.', 'error');
        return;
      }

      producto.tipoOferta = tipo;
      producto.delivery_oferta = deliveryOferta;
      producto.mesa_oferta = mesaOferta;
    }

    carta.productos.push(producto);
    productosExpandidos.add(producto.id);
    marcarCambios();
    cerrarFormularioProducto();
    renderizarCategorias();
    renderizarDetalleCategoria();
    mostrarEstado(el.estado, 'Producto agregado. Guardá para publicarlo.', 'pendiente');
  }

  function crearSlug(texto) {
    return (PM.slugify(texto).slice(0, 40) || 'producto');
  }

  function crearIdCategoriaUnico(nombre) {
    const base = (PM.slugify(nombre).slice(0, 32) || 'categoria');
    let id = base;
    let contador = 2;
    while (categoriaValida(id)) {
      id = `${base}_${contador}`;
      contador += 1;
    }
    return id;
  }

  function abrirModalCategoria(modo, id) {
    tokenUploadCategoria += 1;
    subiendoCategoria = false;
    modalCategoriaModo = modo;
    categoriaEditandoId = id || null;
    fotoCategoriaSeleccionada = '';
    el.formCategoria.reset();
    if (el.categoriaFotoFile) el.categoriaFotoFile.value = '';
    mostrarEstado(el.categoriaEstado, '');
    mostrarEstado(el.categoriaFotoEstado, '');
    actualizarBotonGuardarCategoria();

    if (modo === 'editar') {
      const cat = categoriaPorId(id);
      if (!cat) return;
      if (el.modalCategoriaTitulo) el.modalCategoriaTitulo.textContent = 'Editar categoría';
      el.categoriaNombre.value = cat.nombre || '';
      fotoCategoriaSeleccionada = rutaImagenCategoria(cat);
      if (el.categoriaFotoPreview) {
        el.categoriaFotoPreview.dataset.fallback = '';
        el.categoriaFotoPreview.src = fotoCategoriaSeleccionada;
      }
    } else {
      if (el.modalCategoriaTitulo) el.modalCategoriaTitulo.textContent = 'Nueva categoría';
      if (el.categoriaFotoPreview) {
        el.categoriaFotoPreview.dataset.fallback = '';
        el.categoriaFotoPreview.src = 'assets/logo.webp';
      }
    }

    el.modalCategoria.hidden = false;
    document.body.classList.add('admin-modal-abierto');

    requestAnimationFrame(() => {
      if (el.categoriaNombre) el.categoriaNombre.focus({ preventScroll: true });
    });
  }

  function cerrarModalCategoria() {
    tokenUploadCategoria += 1;
    subiendoCategoria = false;
    modalCategoriaModo = 'crear';
    categoriaEditandoId = null;
    fotoCategoriaSeleccionada = '';
    if (el.modalCategoria) el.modalCategoria.hidden = true;
    if (el.formCategoria) el.formCategoria.reset();
    if (el.categoriaFotoFile) el.categoriaFotoFile.value = '';
    if (el.categoriaFotoPreview) {
      el.categoriaFotoPreview.dataset.fallback = '';
      el.categoriaFotoPreview.src = 'assets/logo.webp';
    }
    mostrarEstado(el.categoriaEstado, '');
    mostrarEstado(el.categoriaFotoEstado, '');
    document.body.classList.remove('admin-modal-abierto');
    actualizarBotonGuardarCategoria();
  }

  async function subirImagenCategoria(archivo) {
    try {
      validarArchivoImagen(archivo);
    } catch (error) {
      mostrarEstado(el.categoriaFotoEstado, error.message, 'error');
      return;
    }

    const token = ++tokenUploadCategoria;
    const previewAnterior = el.categoriaFotoPreview ? el.categoriaFotoPreview.src : '';
    const previewTemporal = crearPreviewTemporal(archivo);
    let subidaOk = false;

    if (previewTemporal) aplicarPreviewImagen(el.categoriaFotoPreview, previewTemporal);

    subiendoCategoria = true;
    actualizarBotonGuardarCategoria();
    mostrarEstado(el.categoriaFotoEstado, 'Subiendo imagen...', 'pendiente');

    try {
      const url = await subirImagen(archivo, 'categorias');
      if (token !== tokenUploadCategoria) return;
      fotoCategoriaSeleccionada = url;
      subidaOk = true;
      aplicarPreviewImagen(el.categoriaFotoPreview, url);
      mostrarEstado(el.categoriaFotoEstado, 'Imagen lista', 'ok');
    } catch (error) {
      if (token === tokenUploadCategoria) {
        if (previewAnterior) aplicarPreviewImagen(el.categoriaFotoPreview, previewAnterior);
        mostrarEstado(el.categoriaFotoEstado, `Error: ${error.message}`, 'error');
      }
      mostrarAviso('No se pudo subir la imagen. Verificá que el bucket carta-imagenes y sus permisos existan.', 'error');
    } finally {
      if (previewTemporal) {
        if (token === tokenUploadCategoria && !subidaOk && previewAnterior) {
          aplicarPreviewImagen(el.categoriaFotoPreview, previewAnterior);
        }
        revocarPreviewTemporal(previewTemporal);
      }
      if (token === tokenUploadCategoria) {
        subiendoCategoria = false;
        actualizarBotonGuardarCategoria();
      }
    }
  }

  function guardarCategoria(evento) {
    evento.preventDefault();
    if (subiendoCategoria) {
      mostrarEstado(el.categoriaEstado, 'Esperá a que termine de subir la imagen.', 'pendiente');
      return;
    }

    const nombre = el.categoriaNombre.value.trim();
    if (!nombre) {
      mostrarEstado(el.categoriaEstado, 'Escribí un nombre para la categoría.', 'error');
      return;
    }

    if (modalCategoriaModo === 'editar') {
      const cat = categoriaPorId(categoriaEditandoId);
      if (!cat) {
        mostrarEstado(el.categoriaEstado, 'La categoría ya no existe.', 'error');
        return;
      }
      cat.nombre = nombre;
      cat.foto = fotoCategoriaSeleccionada || rutaImagenCategoria(cat);
      cerrarModalCategoria();
      marcarCambios();
      renderizarTodo();
      mostrarEstado(el.estado, 'Categoría actualizada. Guardá para publicar.', 'pendiente');
      return;
    }

    const id = crearIdCategoriaUnico(nombre);
    const nueva = {
      id: id,
      nombre: nombre,
      foto: fotoCategoriaSeleccionada || 'assets/logo.webp'
    };

    carta.categorias.push(nueva);
    cerrarModalCategoria();
    marcarCambios();
    seleccionarCategoria(id, true);
    mostrarEstado(el.estado, 'Categoría creada. Agregá sus productos y guardá.', 'pendiente');
  }

  function validarCarta() {
    if (!carta) return 'La carta no está cargada.';
    if (!Array.isArray(carta.categorias) || !carta.categorias.length) return 'La carta necesita al menos una categoría.';

    const categorias = new Set();
    for (const cat of carta.categorias) {
      if (!cat || !String(cat.id || '').trim()) return 'Hay una categoría sin ID interno.';
      if (!PM.validarId(cat.id)) return `La categoría "${cat.nombre || cat.id}" tiene un ID inválido. Usá minúsculas, números y guiones bajos.`;
      if (categorias.has(cat.id)) return `La categoría "${cat.id}" está duplicada.`;
      categorias.add(cat.id);
    }

    const ids = new Set();
    for (const producto of carta.productos) {
      if (!producto) return 'Hay un producto inválido en la carta.';
      const id = String(producto.id || '').trim();
      const nombre = String(producto.nombre || '').trim();
      if (!id) return 'Hay un producto sin ID interno.';
      if (!PM.validarId(id)) return `El producto "${nombre || id}" tiene un ID inválido. Usá minúsculas, números y guiones bajos.`;
      if (ids.has(id)) return `El ID "${id}" está duplicado.`;
      ids.add(id);
      if (!nombre) return 'Todos los productos necesitan un nombre.';
      if (!categorias.has(producto.categoria)) return `"${nombre}" tiene una categoría inválida.`;
      if (!id.startsWith(`${producto.categoria}_`)) return `El ID "${id}" debe empezar con "${producto.categoria}_".`;
    }

    return '';
  }

  function normalizarCartaParaGuardar() {
    if (!carta) return;

    carta.categorias.forEach(cat => {
      if (!cat) return;
      cat.nombre = String(cat.nombre || cat.id || '').trim() || cat.id;
      cat.foto = String(cat.foto || '').trim();
      if (!esRutaImagenSegura(cat.foto)) cat.foto = 'assets/logo.webp';
      if (!cat.foto) cat.foto = 'assets/logo.webp';
    });

    carta.productos.forEach(producto => {
      if (!producto) return;

      producto.nombre = String(producto.nombre || '').trim() || producto.id;
      producto.descripcion = String(producto.descripcion || '').trim();
      if (!producto.descripcion) delete producto.descripcion;

      if (!producto.precios || typeof producto.precios !== 'object') producto.precios = {};
      ['delivery', 'mesa'].forEach(campo => {
        const numero = Number(producto.precios[campo]);
        producto.precios[campo] = Number.isFinite(numero) && numero >= 0 ? numero : 0;
      });

      const tipo = tipoOfertaProducto(producto);
      if (tipo) {
        const deliveryOferta = Number(producto.delivery_oferta);
        const mesaOferta = Number(producto.mesa_oferta);
        const delivery = producto.precios.delivery;
        const mesa = producto.precios.mesa;
        if (Number.isFinite(deliveryOferta) && deliveryOferta > 0 && deliveryOferta < delivery &&
            Number.isFinite(mesaOferta) && mesaOferta > 0 && mesaOferta < mesa) {
          producto.tipoOferta = tipo;
          producto.delivery_oferta = deliveryOferta;
          producto.mesa_oferta = mesaOferta;
        } else {
          delete producto.tipoOferta;
          delete producto.delivery_oferta;
          delete producto.mesa_oferta;
        }
      } else {
        delete producto.tipoOferta;
        delete producto.delivery_oferta;
        delete producto.mesa_oferta;
      }

      producto.foto = String(producto.foto || '').trim();
      if (!esRutaImagenSegura(producto.foto)) producto.foto = rutaImagenCategoria(categoriaPorId(producto.categoria));

      if (!Array.isArray(producto.sucursales) || producto.sucursales.length === 0) {
        producto.sucursales = SUCURSALES_POR_DEFECTO.slice();
      }

      PM.normalizarAgotado(producto);
      if (typeof producto.agotado !== 'boolean') producto.agotado = false;
      if (producto.agotado_fecha === undefined) producto.agotado_fecha = null;
      if (typeof producto.agotado_hasta_nuevo_aviso !== 'boolean') {
        producto.agotado_hasta_nuevo_aviso = false;
      }
    });
  }

  async function guardarCarta() {
    if (!cliente) {
      mostrarEstado(el.estado, 'Supabase no está disponible.', 'error');
      return;
    }
    if (!carta || guardando) return;

    if (subidasPendientes > 0) {
      mostrarEstado(el.estado, 'Esperá a que terminen de subir las imágenes.', 'pendiente');
      return;
    }

    const errorValidacion = validarCarta();
    if (errorValidacion) {
      mostrarEstado(el.estado, errorValidacion, 'error');
      mostrarAviso('Corregí los datos marcados antes de publicar.', 'error');
      return;
    }

    if (publicacionLocalRiesgosa) {
      const confirmado = window.confirm(
        'No se pudo leer la carta desde Supabase. Si publicás ahora, podrías pisar cambios hechos en otro dispositivo. ¿Publicar igual la copia local?'
      );
      if (!confirmado) {
        mostrarEstado(el.estado, 'Publicación cancelada.', 'pendiente');
        return;
      }
    }

    normalizarCartaParaGuardar();
    guardando = true;
    actualizarBotonGuardar();
    mostrarEstado(el.estado, 'Guardando en la nube...');

    try {
      const { error } = await cliente
        .from(tablaCarta())
        .upsert({
          id: filaCarta(),
          contenido: carta
        }, { onConflict: 'id' });

      if (error) throw error;

      cambiosPendientes = false;
      publicacionLocalRiesgosa = false;
      renderizarTodo();
      mostrarEstado(el.estado, 'Guardado y publicado en tiempo real', 'ok');
      mostrarAviso('');
    } catch (error) {
      const mensaje = error && error.message ? error.message : 'Error desconocido';
      mostrarEstado(el.estado, `No se pudo guardar: ${mensaje}`, 'error');
      mostrarAviso('Verificá que hayas ejecutado las migraciones 001 y 002, que el email esté en la tabla admins y que la sesión siga activa.', 'error');
    } finally {
      guardando = false;
      actualizarBotonGuardar();
    }
  }

  function exportarCarta() {
    if (!carta) return;
    const blob = new Blob([JSON.stringify(carta, null, 2) + '\n'], { type: 'application/json;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const enlace = document.createElement('a');
    enlace.href = url;
    enlace.download = 'cartas.json';
    document.body.appendChild(enlace);
    enlace.click();
    enlace.remove();
    URL.revokeObjectURL(url);
    mostrarEstado(el.estado, 'JSON exportado', 'ok');
  }

  async function iniciarSesion(evento) {
    evento.preventDefault();
    if (!cliente) {
      mostrarEstado(el.loginEstado, 'Supabase no está configurado o no se pudo cargar.', 'error');
      return;
    }

    const email = el.emailInput.value.trim();
    const password = el.passwordInput.value;

    if (!email || !password) {
      mostrarEstado(el.loginEstado, 'Completá el email y la contraseña.', 'error');
      return;
    }

    el.btnLogin.disabled = true;
    mostrarEstado(el.loginEstado, 'Ingresando...');

    try {
      // AQUÍ ESTÁ LA CORRECCIÓN: Autenticación real con Supabase Auth
      const { error } = await cliente.auth.signInWithPassword({ email, password });
      if (error) {
        mostrarEstado(el.loginEstado, 'No se pudo ingresar: ' + error.message, 'error');
        return;
      }
      mostrarEstado(el.loginEstado, '');
    } catch (error) {
      mostrarEstado(el.loginEstado, 'No se pudo ingresar: ' + (error.message || 'error de conexión'), 'error');
    } finally {
      el.btnLogin.disabled = false;
    }
  }

  async function cerrarSesion() {
    if (!cliente) return;
    try {
      await cliente.auth.signOut();
    } catch (error) {
      console.warn(error);
    }
    cambiosPendientes = false;
    mostrarLogin();
  }

  function abrirSelectorArchivo(input) {
    if (!input) return;
    input.value = '';
    input.click();
  }

  function conectarZonaArchivo(zona, input) {
    if (!zona || !input) return;
    zona.addEventListener('click', (evento) => {
      if (evento.target.closest('button, input, a, label, select, textarea')) return;
      abrirSelectorArchivo(input);
    });
  }

  function conectarEventos() {
    if (el.formLogin) el.formLogin.addEventListener('submit', iniciarSesion);
    if (el.btnLogout) el.btnLogout.addEventListener('click', cerrarSesion);
    if (el.btnGuardar) el.btnGuardar.addEventListener('click', guardarCarta);
    if (el.btnExportar) el.btnExportar.addEventListener('click', exportarCarta);
    if (el.btnRecargar) {
      el.btnRecargar.addEventListener('click', async () => {
        if (cambiosPendientes && !window.confirm('Hay cambios sin guardar. ¿Recargar de todos modos?')) return;
        await cargarCarta();
      });
    }

    if (el.btnNuevaCategoria) el.btnNuevaCategoria.addEventListener('click', () => abrirModalCategoria('crear'));
    if (el.btnEditarCategoria) {
      el.btnEditarCategoria.addEventListener('click', () => {
        if (categoriaActivaId) abrirModalCategoria('editar', categoriaActivaId);
      });
    }
    if (el.btnNuevoProducto) el.btnNuevoProducto.addEventListener('click', abrirFormularioProducto);
    if (el.btnVacioNuevoProducto) el.btnVacioNuevoProducto.addEventListener('click', abrirFormularioProducto);
    if (el.btnCerrarFormProducto) el.btnCerrarFormProducto.addEventListener('click', cerrarFormularioProducto);
    if (el.btnCancelarProducto) el.btnCancelarProducto.addEventListener('click', cerrarFormularioProducto);
    if (el.formProducto) el.formProducto.addEventListener('submit', agregarProducto);

    if (el.btnSubirProducto) {
      el.btnSubirProducto.addEventListener('click', () => abrirSelectorArchivo(el.productoFotoFile));
    }
    conectarZonaArchivo(el.productoFotoZona, el.productoFotoFile);
    if (el.productoFotoFile) {
      el.productoFotoFile.addEventListener('change', () => {
        const archivo = el.productoFotoFile.files[0];
        el.productoFotoFile.value = '';
        if (archivo) subirImagenNueva(archivo);
      });
    }

    if (el.btnCerrarModalCategoria) el.btnCerrarModalCategoria.addEventListener('click', cerrarModalCategoria);
    if (el.btnCancelarCategoria) el.btnCancelarCategoria.addEventListener('click', cerrarModalCategoria);
    if (el.modalCategoria) {
      el.modalCategoria.addEventListener('click', (evento) => {
        if (evento.target === el.modalCategoria) cerrarModalCategoria();
      });
    }
    if (el.formCategoria) el.formCategoria.addEventListener('submit', guardarCategoria);
    if (el.btnSubirCategoria) {
      el.btnSubirCategoria.addEventListener('click', () => abrirSelectorArchivo(el.categoriaFotoFile));
    }
    conectarZonaArchivo(el.categoriaFotoZona, el.categoriaFotoFile);
    if (el.categoriaFotoFile) {
      el.categoriaFotoFile.addEventListener('change', () => {
        const archivo = el.categoriaFotoFile.files[0];
        el.categoriaFotoFile.value = '';
        if (archivo) subirImagenCategoria(archivo);
      });
    }

    if (el.listaCategorias) {
      el.listaCategorias.addEventListener('click', (evento) => {
        const boton = evento.target.closest('[data-accion]');
        if (!boton) return;
        const id = boton.dataset.id;
        if (boton.dataset.accion === 'editar-categoria') abrirModalCategoria('editar', id);
        else if (boton.dataset.accion === 'seleccionar-categoria') seleccionarCategoria(id, true);
      });

      el.listaCategorias.addEventListener('error', (evento) => {
        const imagen = evento.target;
        if (!imagen || !imagen.classList || !imagen.classList.contains('admin-cat-foto')) return;
        if (imagen.dataset.fallback === '1') return;
        imagen.dataset.fallback = '1';
        imagen.src = 'assets/logo.webp';
      }, true);
    }

    if (el.listaProductos) {
      el.listaProductos.addEventListener('input', (evento) => {
        const control = evento.target.closest('[data-campo-producto]');
        if (control && control.tagName !== 'SELECT') actualizarCampoProducto(control);
      });

      el.listaProductos.addEventListener('change', (evento) => {
        const archivo = evento.target.closest('[data-file-producto]');
        if (archivo) {
          const card = archivo.closest('[data-id]');
          const seleccionado = archivo.files[0];
          archivo.value = '';
          if (card && seleccionado) subirImagenProducto(card.dataset.id, seleccionado);
          return;
        }

        const control = evento.target.closest('[data-campo-producto]');
        if (control && control.tagName === 'SELECT') actualizarCampoProducto(control);
      });

      el.listaProductos.addEventListener('click', (evento) => {
        const zona = evento.target.closest('[data-upload-zona]');
        const boton = evento.target.closest('[data-accion]');

        if (boton) {
          const id = boton.dataset.id;
          const accion = boton.dataset.accion;

          if (accion === 'toggle-producto') toggleProducto(id);
          else if (accion === 'eliminar-producto') eliminarProducto(id);
          else if (accion === 'subir-imagen-producto') {
            const archivo = zona ? zona.querySelector('[data-file-producto]') : null;
            abrirSelectorArchivo(archivo);
          }
          return;
        }

        if (!zona || evento.target.closest('button, input, a, label, select, textarea')) return;
        abrirSelectorArchivo(zona.querySelector('[data-file-producto]'));
      });

      el.listaProductos.addEventListener('error', (evento) => {
        const imagen = evento.target;
        if (!imagen || !imagen.classList) return;
        if (!imagen.classList.contains('admin-prod-thumb') && !imagen.classList.contains('admin-upload-preview')) return;
        if (imagen.dataset.fallback === '1') return;
        imagen.dataset.fallback = '1';
        imagen.src = 'assets/logo.webp';
      }, true);
    }

    if (el.detalleFoto) {
      el.detalleFoto.addEventListener('error', () => {
        if (el.detalleFoto.dataset.fallback === '1') return;
        el.detalleFoto.dataset.fallback = '1';
        el.detalleFoto.src = 'assets/logo.webp';
      });
    }

    if (el.productoFotoPreview) {
      el.productoFotoPreview.addEventListener('error', () => {
        if (el.productoFotoPreview.dataset.fallback === '1') return;
        el.productoFotoPreview.dataset.fallback = '1';
        el.productoFotoPreview.src = 'assets/logo.webp';
      });
    }

    if (el.categoriaFotoPreview) {
      el.categoriaFotoPreview.addEventListener('error', () => {
        if (el.categoriaFotoPreview.dataset.fallback === '1') return;
        el.categoriaFotoPreview.dataset.fallback = '1';
        el.categoriaFotoPreview.src = 'assets/logo.webp';
      });
    }

    document.addEventListener('keydown', (evento) => {
      if (evento.key !== 'Escape') return;
      if (el.modalCategoria && !el.modalCategoria.hidden) {
        cerrarModalCategoria();
        return;
      }
      if (el.panelNuevoProducto && !el.panelNuevoProducto.hidden) cerrarFormularioProducto();
    });

    window.addEventListener('beforeunload', (evento) => {
      if (!cambiosPendientes) return;
      evento.preventDefault();
      evento.returnValue = '';
    });
  }

  async function iniciar() {
    conectarEventos();
    await Promise.all([cargarConfig(), cargarSucursalesConfig()]);

    const configOk = configValida();
    if (el.configPendiente) {
      el.configPendiente.hidden = configOk;
      el.configPendiente.open = !configOk;
    }

    if (el.emailWrap) el.emailWrap.hidden = false;
    if (el.emailInput) el.emailInput.required = true;

    if (!configOk) {
      mostrarEstado(el.loginEstado, 'Falta configurar data/nube.json para conectar la base de datos.', 'error');
      el.btnLogin.disabled = true;
      return;
    }

    if (!inicializarCliente()) {
      if (el.configPendiente) el.configPendiente.hidden = false;
      mostrarEstado(el.loginEstado, 'No se pudo cargar el cliente de Supabase. Revisá la conexión.', 'error');
      el.btnLogin.disabled = true;
      return;
    }

    // Configurar el observador de sesión una única vez de forma global
    cliente.auth.onAuthStateChange((evento, sesion) => {
      if (sesion && sesion.user) {
        if (el.panel && el.panel.hidden) mostrarPanel(sesion.user);
      } else {
        mostrarLogin();
      }
    });

    try {
      const { data } = await cliente.auth.getSession();
      if (data && data.session && data.session.user) {
        await mostrarPanel(data.session.user);
      } else {
        mostrarLogin();
      }
    } catch (error) {
      mostrarLogin();
      mostrarEstado(el.loginEstado, 'No se pudo comprobar la sesión: ' + (error.message || 'error de conexión'), 'error');
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', iniciar);
  } else {
    iniciar();
  }
})();