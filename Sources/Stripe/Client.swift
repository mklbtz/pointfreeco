import Either
import Foundation
import Optics
import Prelude
import PointFreePrelude
import Tagged
import UrlFormEncoding

public struct Client {
  public var cancelSubscription: (Subscription.Id) -> EitherIO<Error, Subscription>
  public var createCustomer: (Token.Id, String?, EmailAddress?, Customer.Vat?) -> EitherIO<Error, Customer>
  public var createSubscription: (Customer.Id, Plan.Id, Int, Coupon.Id?) -> EitherIO<Error, Subscription>
  public var fetchCoupon: (Coupon.Id) -> EitherIO<Error, Coupon>
  public var fetchCustomer: (Customer.Id) -> EitherIO<Error, Customer>
  public var fetchInvoice: (Invoice.Id) -> EitherIO<Error, Invoice>
  public var fetchInvoices: (Customer.Id) -> EitherIO<Error, ListEnvelope<Invoice>>
  public var fetchPlans: () -> EitherIO<Error, ListEnvelope<Plan>>
  public var fetchPlan: (Plan.Id) -> EitherIO<Error, Plan>
  public var fetchSubscription: (Subscription.Id) -> EitherIO<Error, Subscription>
  public var fetchUpcomingInvoice: (Customer.Id) -> EitherIO<Error, Invoice>
  public var invoiceCustomer: (Customer.Id) -> EitherIO<Error, Invoice>
  public var updateCustomer: (Customer.Id, Token.Id) -> EitherIO<Error, Customer>
  public var updateCustomerExtraInvoiceInfo: (Customer.Id, String) -> EitherIO<Error, Customer>
  public var updateSubscription: (Subscription, Plan.Id, Int, Bool?) -> EitherIO<Error, Subscription>
  public var js: String
}

extension Client {
  public init(secretKey: String) {
    self.init(
      cancelSubscription: Stripe.cancelSubscription >>> runStripe(secretKey),
      createCustomer: { Stripe.createCustomer(token: $0, description: $1, email: $2, vatNumber: $3) |> runStripe(secretKey) },
      createSubscription: { Stripe.createSubscription(customer: $0, plan: $1, quantity: $2, coupon: $3) |> runStripe(secretKey) },
      fetchCoupon: Stripe.fetchCoupon >>> runStripe(secretKey),
      fetchCustomer: Stripe.fetchCustomer >>> runStripe(secretKey),
      fetchInvoice: Stripe.fetchInvoice >>> runStripe(secretKey),
      fetchInvoices: Stripe.fetchInvoices >>> runStripe(secretKey),
      fetchPlans: { Stripe.fetchPlans() |> runStripe(secretKey) },
      fetchPlan: Stripe.fetchPlan >>> runStripe(secretKey),
      fetchSubscription: Stripe.fetchSubscription >>> runStripe(secretKey),
      fetchUpcomingInvoice: Stripe.fetchUpcomingInvoice >>> runStripe(secretKey),
      invoiceCustomer: Stripe.invoiceCustomer >>> runStripe(secretKey),
      updateCustomer: { Stripe.updateCustomer(id: $0, token: $1) |> runStripe(secretKey) },
      updateCustomerExtraInvoiceInfo: { Stripe.updateCustomer(id: $0, extraInvoiceInfo: $1) |> runStripe(secretKey) },
      updateSubscription: { Stripe.updateSubscription($0, $1, $2, $3) |> runStripe(secretKey) },
      js: "https://js.stripe.com/v3/"
    )
  }
}

func cancelSubscription(id: Subscription.Id) -> DecodableRequest<Subscription> {
  return stripeRequest(
    "subscriptions/" + id.rawValue + "?expand[]=customer", .delete(["at_period_end": "true"])
  )
}

func createCustomer(
  token: Token.Id,
  description: String?,
  email: EmailAddress?,
  vatNumber: Customer.Vat?
  )
  -> DecodableRequest<Customer> {

    return stripeRequest("customers", .post(filteredValues <| [
      "business_vat_id": vatNumber?.rawValue,
      "description": description,
      "email": email?.rawValue,
      "source": token.rawValue,
      ]))
}

func createSubscription(
  customer: Customer.Id,
  plan: Plan.Id,
  quantity: Int,
  coupon: Coupon.Id?
  )
  -> DecodableRequest<Subscription> {

    var params: [String: Any] = [:]
    params["customer"] = customer.rawValue
    params["items[0][plan]"] = plan.rawValue
    params["items[0][quantity]"] = String(quantity)
    params["coupon"] = coupon?.rawValue

    return stripeRequest("subscriptions?expand[]=customer", .post(params))
}

func fetchCoupon(id: Coupon.Id) -> DecodableRequest<Coupon> {
  return stripeRequest("coupons/" + id.rawValue)
}

func fetchCustomer(id: Customer.Id) -> DecodableRequest<Customer> {
  return stripeRequest("customers/" + id.rawValue)
}

func fetchInvoice(id: Invoice.Id) -> DecodableRequest<Invoice> {
  return stripeRequest("invoices/" + id.rawValue + "?expand[]=charge")
}

func fetchInvoices(for customer: Customer.Id) -> DecodableRequest<ListEnvelope<Invoice>> {
  return stripeRequest("invoices?customer=" + customer.rawValue + "&expand[]=data.charge&limit=100")
}

func fetchPlans() -> DecodableRequest<ListEnvelope<Plan>> {
  return stripeRequest("plans")
}

func fetchPlan(id: Plan.Id) -> DecodableRequest<Plan> {
  return stripeRequest("plans/" + id.rawValue)
}

func fetchSubscription(id: Subscription.Id) -> DecodableRequest<Subscription> {
  return stripeRequest("subscriptions/" + id.rawValue + "?expand[]=customer")
}

func fetchUpcomingInvoice(_ customer: Customer.Id) -> DecodableRequest<Invoice> {
  return stripeRequest("invoices/upcoming?customer=" + customer.rawValue + "&expand[]=charge")
}

func invoiceCustomer(_ customer: Customer.Id)
  -> DecodableRequest<Invoice> {

    return stripeRequest("invoices", .post([
      "customer": customer.rawValue,
      ]))
}

func updateCustomer(id: Customer.Id, token: Token.Id)
  -> DecodableRequest<Customer> {

    return stripeRequest("customers/" + id.rawValue, .post([
      "source": token.rawValue,
      ]))
}

func updateCustomer(id: Customer.Id, extraInvoiceInfo: String) -> DecodableRequest<Customer> {

  return stripeRequest("customers/" + id.rawValue, .post([
    "metadata": ["extraInvoiceInfo": extraInvoiceInfo],
    ]))
}

func updateSubscription(
  _ currentSubscription: Subscription,
  _ plan: Plan.Id,
  _ quantity: Int,
  _ prorate: Bool?
  )
  -> DecodableRequest<Subscription>? {

    guard let item = currentSubscription.items.data.first else { return nil }

    return stripeRequest("subscriptions/" + currentSubscription.id.rawValue + "?expand[]=customer", .post(filteredValues <| [
      "coupon": "",
      "items[0][id]": item.id.rawValue,
      "items[0][plan]": plan.rawValue,
      "items[0][quantity]": String(quantity),
      "prorate": prorate.map(String.init(describing:)),
      ]))
}

public let jsonDecoder = JSONDecoder()
  |> \.dateDecodingStrategy .~ .secondsSince1970
//  |> \.keyDecodingStrategy .~ .convertFromSnakeCase

public let jsonEncoder = JSONEncoder()
  |> \.dateEncodingStrategy .~ .secondsSince1970
//  |> \.keyEncodingStrategy .~ .convertToSnakeCase

enum Method {
  case get
  case post([String: Any])
  case delete([String: String])
}

private func attachMethod(_ method: Method) -> (URLRequest) -> URLRequest {
  switch method {
  case .get:
    return \.httpMethod .~ "GET"
  case let .post(params):
    return (\.httpMethod .~ "POST")
      <> attachFormData(params)
  case let .delete(params):
    return (\.httpMethod .~ "DELETE")
      <> attachFormData(params)
  }
}

func stripeRequest<A>(_ path: String, _ method: Method = .get) -> DecodableRequest<A> {
  return DecodableRequest(
    rawValue: URLRequest(url: URL(string: "https://api.stripe.com/v1/" + path)!)
      |> attachMethod(method)
  )
}

private func runStripe<A>(_ secretKey: String) -> (DecodableRequest<A>?) -> EitherIO<Error, A> {
  return { stripeRequest in
    guard
      let stripeRequest = stripeRequest?.map(attachBasicAuth(username: secretKey))
      else { return throwE(unit) }

    let task: EitherIO<Error, A> = pure(stripeRequest.rawValue)
      .flatMap {
        dataTask(with: $0)
          .map(first)
          .flatMap { data in
            .wrap {
              do {
                return try jsonDecoder.decode(A.self, from: data)
              } catch {
                throw (try? jsonDecoder.decode(StripeErrorEnvelope.self, from: data))
                  ?? JSONError.error(String(decoding: data, as: UTF8.self), error) as Error
              }
            }
        }
    }

    return task
  }
}
