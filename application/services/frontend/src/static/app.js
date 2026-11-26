const products = [];
const $ = (id) => document.getElementById(id);

async function loadProducts() {
  const res = await fetch("/api/products");
  const data = await res.json();
  $("source").textContent = `served from: ${data.source}`;
  products.splice(0, products.length, ...data.items);
  $("products").innerHTML = products
    .map((p) => `<li><strong>${p.name}</strong> - $${Number(p.price).toFixed(2)} <em>(${p.category})</em></li>`)
    .join("");
  $("product").innerHTML = products.map((p) => `<option value="${p.product_id}">${p.name}</option>`).join("");
}

async function placeOrder(event) {
  event.preventDefault();
  const product = products.find((p) => p.product_id === $("product").value);
  const body = {
    customer: $("customer").value,
    items: [{ product_id: product.product_id, quantity: Number($("qty").value), unit_price: Number(product.price) }],
  };
  const res = await fetch("/api/orders", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const created = await res.json();
  $("result").textContent = JSON.stringify(created, null, 2);
  if (res.ok) pollOrder(created.order_id);
}

// The order is processed asynchronously by the worker (SQS): poll until the status changes.
async function pollOrder(id) {
  for (let i = 0; i < 20; i++) {
    await new Promise((r) => setTimeout(r, 2000));
    const res = await fetch(`/api/orders/${id}`);
    const order = await res.json();
    $("result").textContent = JSON.stringify(order, null, 2);
    if (order.status !== "PENDING") return;
  }
}

$("order-form").addEventListener("submit", placeOrder);
loadProducts().catch((e) => ($("source").textContent = `error: ${e}`));
