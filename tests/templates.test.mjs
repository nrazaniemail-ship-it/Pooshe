import test from "node:test";
import assert from "node:assert/strict";
import {TYPES,makeSteps} from "../src/templates.js";

test("case groups and categories exist",()=>{
 assert.ok(TYPES.حقوقی);assert.ok(TYPES.کیفری);
 for(const g of Object.values(TYPES))for(const x of Object.values(g))assert.ok(x.length);
});
test("workflow steps are ordered and pending",()=>{
 for(const g of ["حقوقی","کیفری"]){
  const s=makeSteps(g);assert.ok(s.length>=10);assert.equal(s[0].order,1);assert.equal(s[0].status,"pending");
  assert.deepEqual(s.map(x=>x.order),s.map((_,i)=>i+1));
 }
});
test("specialized civil check workflow includes check documents and enforcement",()=>{
 const s=makeSteps("حقوقی","مطالبه وجه چک").map(x=>x.title).join(" ");
 assert.match(s,/گواهی عدم پرداخت/);assert.match(s,/اجرائیه/);
});
test("criminal bounced-check workflow uses criminal complaint checks",()=>{
 const s=makeSteps("کیفری","صدور چک بلامحل").map(x=>x.title).join(" ");
 assert.match(s,/مواعد قانونی شکایت/);assert.doesNotMatch(s,/امکان مطالبه از طریق اجرائیه/);
});
test("family and property matters get tailored steps",()=>{
 assert.ok(makeSteps("حقوقی","مهریه").some(x=>x.title.includes("اسناد زوجیت")));
 assert.ok(makeSteps("حقوقی","خلع ید").some(x=>x.title.includes("سوابق ثبتی")));
});
